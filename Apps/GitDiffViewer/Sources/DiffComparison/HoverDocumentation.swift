package import AemiCore
import AtelierDocIndex
package import AtelierLSP
package import AtelierSyntaxModel
package import DiffGit
package import Foundation

/// LSP first when available; the doc-comment index answers otherwise and for git-blob content.
///
/// A `primary` failure (a `nil` answer, a thrown error, or a timeout the language server itself already
/// collapsed to `nil`) falls back to the doc-comment index; a genuine cancellation propagates instead, since
/// nothing downstream should show content for a query nobody is waiting on anymore.
struct TieredHoverProvider: HoverProvider {
    let primary: (any HoverProvider)?
    let fallback: any HoverProvider

    func hover(_ query: HoverQuery) async throws -> HoverContent? {
        if let primary {
            do {
                if let content = try await primary.hover(query) { return content }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Any other failure of the primary tier falls through to the doc-comment index.
            }
        }
        return try await fallback.hover(query)
    }
}

/// Which side of a diff a hover query falls on. Mirrors ``DiffTextKit/HoverSide`` without depending on
/// `DiffTextKit`, which this target has no need of otherwise.
package enum HoverQuerySide: Sendable, Equatable {
    case old
    case new
}

/// The window's hover-documentation state: keeps a doc-comment index fed with both sides of every prepared
/// Swift file, and answers hover hits from it, tiered behind a language server when one is available for the
/// file under the pointer.
@MainActor
package final class HoverDocumentationModel {
    /// One prepared file's identity and full text, as behind the current render.
    package struct FileEntry: Sendable {
        package let index: Int
        /// The path this file is diffed under (the comparison's own key), used for the old side and as a
        /// fallback URI when there is no separate new-side path.
        package let leftPath: String
        /// The new side's own path, when the file has one (nil for a file deleted on the right).
        package let rightPath: String?
        package let oldText: String
        package let newText: String
        package let oldBlobID: String?
        package let newBlobID: String?

        package init(
            index: Int, leftPath: String, rightPath: String?, oldText: String, newText: String,
            oldBlobID: String?, newBlobID: String?
        ) {
            self.index = index
            self.leftPath = leftPath
            self.rightPath = rightPath
            self.oldText = oldText
            self.newText = newText
            self.oldBlobID = oldBlobID
            self.newBlobID = newBlobID
        }
    }

    private let index = DocCommentIndex()
    private let docProvider: DocIndexHoverProvider
    private let lspRegistry: SourceKitLSPRegistry?
    private let taskProvider: any TaskProvider

    private var filesByIndex: [Int: FileEntry] = [:]
    /// The right side's working-tree root; non-nil only for a repository (or plain folder) comparison whose
    /// right side is on disk, i.e. exactly when the language server tier is ever worth trying.
    private var repositoryRoot: URL?
    private var feedTask: Task<Void, Never>?
    /// Bumped by every ``comparisonChanged(root:files:corpusReader:corpusSource:corpusEntries:)``; the background
    /// corpus-broadening pass checks this before it publishes, so a slower, superseded pass can never land after
    /// a newer comparison already replaced it (`feedTask?.cancel()` alone is not enough: cancellation is
    /// cooperative, and the broadening pass checks it only between awaits).
    private var generation = 0

    /// A corpus file too large to be worth parsing for a hover fallback that only serves documentation, not code
    /// intelligence.
    static let maxCorpusFileSize = 512 * 1024
    /// Caps how many files beyond the changeset the background pass reads, so a huge repository comparison never
    /// turns into an unbounded read storm.
    static let maxCorpusFiles = 2000

    /// The on-device Apple SDK tier, injected after construction (it resolves asynchronously, once per app);
    /// nil leaves hovers answered by the language server and doc-comment index alone.
    package var sdkProvider: (any HoverProvider)?

    package init(lspRegistry: SourceKitLSPRegistry?, taskProvider: any TaskProvider = .default) {
        self.lspRegistry = lspRegistry
        self.taskProvider = taskProvider
        docProvider = DocIndexHoverProvider(index: index)
    }

    /// Re-feeds the doc-comment index with both sides of every prepared (changed) Swift file, and remembers the
    /// working tree root (if any) hovers over the new side may resolve a language server against. Fire-and-forget:
    /// a superseded comparison cancels whatever re-index was still running, so a slower, older update can never
    /// land after a newer one.
    ///
    /// Coverage contract: the fast pass above only ever indexes symbols *declared* in a changed file, so a hover
    /// over a symbol declared elsewhere (a type from an unchanged file, say) answers nothing from it alone. When
    /// `corpusReader`, `corpusSource` and `corpusEntries` are given, a second pass follows in the background,
    /// reading every other Swift file the right side already listed (skipping anything over
    /// ``maxCorpusFileSize``, and capped at ``maxCorpusFiles`` files total) and adding it to the index. This is
    /// still best-effort, not exhaustive: a repository with more than ``maxCorpusFiles`` eligible files, or a
    /// symbol declared only in a file the cap skipped, will not resolve through the doc-comment index (the LSP
    /// tier, when one is available for the new side, is unaffected by this cap).
    package func comparisonChanged(
        root: URL?, files: [FileEntry], corpusReader: (any SourceReading)? = nil,
        corpusSource: ComparisonSource? = nil, corpusEntries: [GitTreeEntry] = []
    ) {
        repositoryRoot = root
        filesByIndex = Dictionary(uniqueKeysWithValues: files.map { ($0.index, $0) })

        let docFiles = files.filter { $0.leftPath.hasSuffix(".swift") || ($0.rightPath?.hasSuffix(".swift") ?? false) }
            .flatMap { file in
                [
                    DocIndexFile(
                        uri: Self.uri(path: file.leftPath, blobID: file.oldBlobID, onDiskRoot: nil),
                        content: file.oldText),
                    DocIndexFile(
                        uri: Self.uri(path: file.rightPath ?? file.leftPath, blobID: file.newBlobID, onDiskRoot: root),
                        content: file.newText)
                ]
            }
        let changedRightPaths = Set(files.map { $0.rightPath ?? $0.leftPath })
        generation += 1
        let myGeneration = generation
        feedTask?.cancel()
        feedTask = taskProvider.task { [weak self, index] in
            guard !Task.isCancelled else { return }
            await index.update(files: docFiles)
            guard let self, let corpusReader, let corpusSource, !Task.isCancelled,
                myGeneration == self.generation
            else { return }
            let candidates = Self.corpusCandidates(entries: corpusEntries, excluding: changedRightPaths)
            guard !candidates.isEmpty else { return }
            guard let contents = try? await corpusReader.contents(of: candidates, in: corpusSource) else { return }
            guard !Task.isCancelled, myGeneration == self.generation else { return }
            let broadFiles =
                docFiles
                + candidates.compactMap { entry in
                    contents[entry.relativePath]
                        .map {
                            DocIndexFile(
                                uri: Self.uri(path: entry.relativePath, blobID: entry.blobID, onDiskRoot: root),
                                content: $0)
                        }
                }
            await index.update(files: broadFiles)
        }
    }

    /// The right side's other Swift files a background pass should add to the corpus: everything not already fed
    /// by the changeset, small enough to be worth parsing, up to ``maxCorpusFiles``.
    private static func corpusCandidates(entries: [GitTreeEntry], excluding changed: Set<String>) -> [GitTreeEntry] {
        Array(
            entries.filter {
                $0.relativePath.hasSuffix(".swift") && !changed.contains($0.relativePath)
                    && $0.size <= maxCorpusFileSize
            }
            .prefix(maxCorpusFiles))
    }

    /// Answers a hover hit at `fileIndex`/`side`/`line`/`utf16Column` (the same coordinates
    /// ``DiffTextKit/HoverHit`` carries): the language server first when the hit is on the new side of an
    /// on-disk Swift file, the doc-comment index otherwise.
    package func hover(fileIndex: Int, side: HoverQuerySide, line: Int, utf16Column: Int) async -> HoverContent? {
        guard let file = filesByIndex[fileIndex] else { return nil }
        let content = side == .new ? file.newText : file.oldText
        guard !content.isEmpty else { return nil }
        let path = side == .new ? (file.rightPath ?? file.leftPath) : file.leftPath
        let blobID = side == .new ? file.newBlobID : file.oldBlobID
        let onDiskRoot = side == .new ? repositoryRoot : nil
        let uri = Self.uri(path: path, blobID: blobID, onDiskRoot: onDiskRoot)
        let query = HoverQuery(documentURI: uri, content: content, line: line, utf16Column: utf16Column)

        let primary = await primaryProvider(side: side, path: path, onDiskRoot: onDiskRoot)
        let tiers = [primary, docProvider, sdkProvider].compactMap { $0 }
        return try? await TieredHoverProviders(tiers).hover(query)
    }

    private func primaryProvider(side: HoverQuerySide, path: String, onDiskRoot: URL?) async -> (any HoverProvider)? {
        guard side == .new, let onDiskRoot, let lspRegistry,
            Language(fileExtension: URL(filePath: path).pathExtension) == .swift
        else { return nil }
        guard let service = await lspRegistry.service(forRoot: onDiskRoot) else { return nil }
        return LSPHoverProvider(service: service)
    }

    /// A `file://` URI under `onDiskRoot` when given, or a synthetic `atelier-blob://<oid>/<path>` URI otherwise
    /// -- the shape ``HoverQuery/documentURI`` documents, so both an on-disk file and a git blob (or a missing
    /// hash, which falls back to a fixed placeholder oid) can be told apart and cached by a language server.
    /// Internal rather than private so a test can check the shape directly.
    static func uri(path: String, blobID: String?, onDiskRoot: URL?) -> String {
        if let onDiskRoot {
            return onDiskRoot.appending(path: path).absoluteString
        }
        return "atelier-blob://\(blobID ?? "unknown")/\(path)"
    }
}
