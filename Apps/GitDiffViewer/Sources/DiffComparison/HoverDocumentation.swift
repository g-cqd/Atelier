package import AemiCore
import AtelierDocIndex
package import AtelierLSP
package import AtelierSyntaxModel
package import DiffGit
package import Foundation

/// LSP first when available; the doc-comment index answers otherwise and for git-blob content. Any `primary`
/// failure falls back to the index; a cancellation propagates.
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

/// Which side of a diff a hover query falls on; mirrors ``DiffTextKit/HoverSide`` without depending on it.
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
        /// The path the comparison keys this file by, used for the old side and when there is no new-side path.
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
    /// The right side's on-disk root, canonical as the language server registry keys it, so the server's workspace
    /// and every document URI spell the root alike; nil when the right side is not on disk.
    private var repositoryRoot: URL?
    /// The last root ``comparisonChanged(root:files:corpusReader:corpusSource:corpusEntries:)`` got, as given, so
    /// every publish of one comparison resolves its canonical form once it resolves.
    private var lastGivenRoot: URL?
    private var feedTask: Task<Void, Never>?
    /// Bumped by every comparison change; a superseded corpus pass drops its result, since cancellation is only
    /// checked between awaits.
    private var generation = 0

    /// The largest corpus file, in bytes, the background pass parses.
    static let maxCorpusFileSize = 512 * 1024
    /// The most files beyond the changeset the background pass reads.
    static let maxCorpusFiles = 2000

    /// The on-device Apple SDK tier, injected once it resolves; nil leaves hovers to the language server and the
    /// doc-comment index.
    package var sdkProvider: (any HoverProvider)?

    package init(lspRegistry: SourceKitLSPRegistry?, taskProvider: any TaskProvider = .default) {
        self.lspRegistry = lspRegistry
        self.taskProvider = taskProvider
        docProvider = DocIndexHoverProvider(index: index)
    }

    /// Re-feeds the doc-comment index with both sides of every changed Swift file, and remembers `root`'s canonical
    /// form for the language server tier; a root that names no existing directory counts as not on disk. Given a
    /// corpus reader, source and entries, a background pass then adds the right side's other Swift files, within
    /// ``maxCorpusFileSize`` and ``maxCorpusFiles``. A newer call supersedes any feed still running.
    package func comparisonChanged(
        root givenRoot: URL?, files: [FileEntry], corpusReader: (any SourceReading)? = nil,
        corpusSource: ComparisonSource? = nil, corpusEntries: [GitTreeEntry] = []
    ) {
        if givenRoot != lastGivenRoot || repositoryRoot == nil {
            lastGivenRoot = givenRoot
            repositoryRoot = givenRoot.flatMap(SourceKitLSPRegistry.canonicalRoot)
        }
        let root = repositoryRoot
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

    /// The Swift files outside the changeset within ``maxCorpusFileSize``, at most ``maxCorpusFiles`` of them.
    private static func corpusCandidates(entries: [GitTreeEntry], excluding changed: Set<String>) -> [GitTreeEntry] {
        Array(
            entries.filter {
                $0.relativePath.hasSuffix(".swift") && !changed.contains($0.relativePath)
                    && $0.size <= maxCorpusFileSize
            }
            .prefix(maxCorpusFiles))
    }

    /// Answers a hover hit, in ``DiffTextKit/HoverHit``'s coordinates, through ``AtelierLSP/TieredHoverProviders``:
    /// the language server (new side of an on-disk Swift file only), the doc-comment index, then the SDK tier.
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

    /// A `file://` URI under `onDiskRoot` when given, or a synthetic `atelier-blob://<oid>/<path>` URI otherwise,
    /// the shape ``HoverQuery/documentURI`` documents.
    static func uri(path: String, blobID: String?, onDiskRoot: URL?) -> String {
        if let onDiskRoot {
            return onDiskRoot.appending(path: path).absoluteString
        }
        return "atelier-blob://\(blobID ?? "unknown")/\(path)"
    }
}
