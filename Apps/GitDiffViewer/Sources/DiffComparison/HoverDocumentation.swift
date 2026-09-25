package import AemiCore
package import AtelierDocIndex
package import AtelierLSP
package import AtelierSyntaxModel
package import DiffGit
package import Foundation
import os

/// Which side of a diff a hover query falls on; mirrors ``DiffTextKit/HoverSide`` without depending on it.
package enum HoverQuerySide: Sendable, Equatable {
    case old
    case new
}

/// The window's hover-documentation state: keeps a doc-comment index fed with both sides of every prepared Swift
/// file and with the right side's other Swift files, the corpus, and answers hover hits from it, tiered behind a
/// language server when one is available for the file under the pointer.
///
/// A feed indexes only what changed. A feed identical to the last does nothing; a changeset file keeps its entries
/// while its blob id stays the same; the corpus pass reads only the files not indexed at their blob id. The index
/// holds the current comparison alone, so it stays bounded however many comparisons a window shows, and each file
/// answers for its own side, so a hover never lists the other side's version of a declaration.
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

        var isSwift: Bool { leftPath.hasSuffix(".swift") || (rightPath?.hasSuffix(".swift") ?? false) }

        /// Whether a side has text but no blob id, as a working-tree file too large to hash: its text can change
        /// while nothing else about the feed does. A side with no text is a missing side.
        var hasUnhashedSide: Bool {
            (oldBlobID == nil && !oldText.isEmpty) || (newBlobID == nil && !newText.isEmpty)
        }
    }

    private let index: DocCommentIndex
    /// The doc-comment tier of each side: a hover lists only its own side's declarations, and each side keeps the
    /// document it parsed last.
    private let oldSideDocs: DocIndexHoverProvider
    private let newSideDocs: DocIndexHoverProvider
    private let lspRegistry: LanguageServerRegistry?
    private let taskProvider: any TaskProvider

    private var filesByIndex: [Int: FileEntry] = [:]
    /// The right side's on-disk root, canonical as the language server registry keys it, so the server's workspace
    /// and every document URI spell the root alike; nil when the right side is not on disk.
    private var repositoryRoot: URL?
    /// The last root ``comparisonChanged(root:files:corpusReader:corpusSource:corpusEntries:)`` got, as given, so
    /// every publish of one comparison resolves its canonical form once it resolves.
    private var lastGivenRoot: URL?
    /// What the last feed asked for; a feed with the same identity has nothing new to index. Nil runs the next feed
    /// whatever it is.
    private var lastFeed: HoverFeed.Identity?
    /// Indexes a feed's changeset, the files on screen.
    private var changesetTask: Task<Void, any Error>?
    /// Reads and indexes a feed's corpus once its changeset has landed.
    private var corpusTask: Task<Void, any Error>?

    /// The largest corpus file, in bytes, the background pass parses.
    nonisolated static let maxCorpusFileSize = 512 * 1024
    /// The most files beyond the changeset the background pass reads.
    nonisolated static let maxCorpusFiles = 2000
    /// The corpus files read and parsed per step: a superseded pass stops at the next step, and no more than this
    /// many files' text is held at once.
    static let corpusChunkSize = 64

    private static let logger = Logger(subsystem: "fr.gcqd.GitDiffViewer", category: "HoverDocumentation")

    /// The on-device Apple SDK tier, injected once it resolves; nil leaves hovers to the language server and the
    /// doc-comment index.
    package var sdkProvider: (any HoverProvider)?

    /// Whether hover documentation is on. While it is off, a feed indexes nothing, and turning it off stops the pass
    /// in flight; the first feed after it turns back on indexes the comparison again.
    package var isEnabled = true {
        didSet {
            guard !isEnabled, oldValue else { return }
            stopFeeding()
            lastFeed = nil
        }
    }

    /// - Parameters:
    ///   - lspRegistry: The language servers of on-disk roots; nil leaves hovers to the index and the SDK tier.
    ///   - taskProvider: Spawns the feeds' passes.
    ///   - index: The doc-comment index the feeds fill, such as one whose parses a test counts.
    package init(
        lspRegistry: LanguageServerRegistry?, taskProvider: any TaskProvider = .default,
        index: DocCommentIndex = DocCommentIndex()
    ) {
        self.lspRegistry = lspRegistry
        self.taskProvider = taskProvider
        self.index = index
        oldSideDocs = DocIndexHoverProvider(index: index, side: .old)
        newSideDocs = DocIndexHoverProvider(index: index, side: .new)
    }

    /// Feeds the doc-comment index both sides of every changed Swift file, and remembers `root`'s canonical form for
    /// the language server tier; a root that names no existing directory counts as not on disk. Given a corpus
    /// reader, source and entries, a background pass then adds the right side's other Swift files, within
    /// ``maxCorpusFileSize`` and ``maxCorpusFiles``, ``corpusChunkSize`` at a time. A newer feed stops the one in
    /// flight; one identical to the last does nothing. With no files, hovers answer nothing and the index keeps what
    /// it holds for the next feed, which a reload makes with the same files.
    package func comparisonChanged(
        root givenRoot: URL?, files: [FileEntry], corpusReader: (any SourceReading)? = nil,
        corpusSource: ComparisonSource? = nil, corpusEntries: [GitTreeEntry] = []
    ) {
        guard isEnabled else { return }
        filesByIndex = Dictionary(uniqueKeysWithValues: files.map { ($0.index, $0) })
        guard !files.isEmpty else { return }
        if givenRoot != lastGivenRoot || repositoryRoot == nil {
            lastGivenRoot = givenRoot
            repositoryRoot = givenRoot.flatMap(LanguageServerRegistry.canonicalRoot)
        }
        let corpus = corpusReader.flatMap { reader in corpusSource.map { (reader: reader, source: $0) } }
        let identity = HoverFeed.Identity(
            root: repositoryRoot, files: files, corpusSource: corpus?.source,
            corpusEntries: corpus == nil ? [] : corpusEntries)
        if let identity, identity == lastFeed { return }
        lastFeed = identity
        stopFeeding()
        let feed = HoverFeed(root: repositoryRoot, files: files, corpusEntries: corpus == nil ? [] : corpusEntries)
        let index = index
        let changesetTask = taskProvider.task(priority: .utility) { () async throws in
            try await index.keepOnly(feed.scope)
            try await index.upsert(feed.changeset)
        }
        self.changesetTask = changesetTask
        guard let corpus, !feed.corpus.isEmpty else { return }
        corpusTask = taskProvider.task(priority: .background) { [weak self] () async throws in
            // The corpus follows the changeset, whose files are the ones on screen.
            _ = await changesetTask.result
            try Task.checkCancellation()
            let unread = await Self.unindexed(feed.corpus, in: index)
            for start in stride(from: 0, to: unread.count, by: Self.corpusChunkSize) {
                try Task.checkCancellation()
                let chunk = Array(unread[start ..< min(start + Self.corpusChunkSize, unread.count)])
                let contents: [String: String]
                do {
                    contents = try await corpus.reader.contents(of: chunk.map(\.entry), in: corpus.source)
                } catch {
                    // A superseded pass stops here. Otherwise the chunk's files stay unindexed, and the next feed,
                    // identical or not, reads them again.
                    try Task.checkCancellation()
                    Self.logger.error("A hover corpus read failed: \(String(describing: error), privacy: .private)")
                    self?.lastFeed = nil
                    continue
                }
                try await index.upsert(
                    chunk.compactMap { file in
                        contents[file.entry.relativePath]
                            .map { DocIndexFile(uri: file.uri, content: $0, blobID: file.entry.blobID, sides: .both) }
                    })
            }
        }
    }

    private func stopFeeding() {
        changesetTask?.cancel()
        corpusTask?.cancel()
        changesetTask = nil
        corpusTask = nil
    }

    /// The corpus files not indexed at their blob id; a file without one is always read.
    private static func unindexed(_ corpus: [HoverFeed.CorpusFile], in index: DocCommentIndex) async
        -> [HoverFeed.CorpusFile]
    {
        let blobIDs = Dictionary(
            corpus.compactMap { file in file.entry.blobID.map { (file.uri, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let indexed = await index.urisIndexed(atBlobIDs: blobIDs)
        return corpus.filter { !indexed.contains($0.uri) }
    }

    /// Answers a hover hit, in ``DiffTextKit/HoverHit``'s coordinates, through ``AtelierLSP/TieredHoverProviders``:
    /// the language server (new side of an on-disk file only), the doc-comment index of the hovered side, then the SDK
    /// tier. Only a Swift file has a hover.
    package func hover(fileIndex: Int, side: HoverQuerySide, line: Int, utf16Column: Int) async -> HoverContent? {
        guard let file = filesByIndex[fileIndex] else { return nil }
        let path = side == .new ? (file.rightPath ?? file.leftPath) : file.leftPath
        // Every tier reads Swift: the language server and the SDK tier ask sourcekit-lsp, and the doc-comment index
        // parses with swift-syntax, to which another language's comments and strings are code whose brackets never
        // close. Another language gets no hover rather than a wrong one, and is never parsed.
        guard Language(fileExtension: URL(filePath: path).pathExtension) == .swift else { return nil }
        let content = side == .new ? file.newText : file.oldText
        guard !content.isEmpty else { return nil }
        let blobID = side == .new ? file.newBlobID : file.oldBlobID
        let onDiskRoot = side == .new ? repositoryRoot : nil
        let uri = Self.uri(path: path, blobID: blobID, onDiskRoot: onDiskRoot)
        let query = HoverQuery(documentURI: uri, content: content, line: line, utf16Column: utf16Column)

        let primary = await primaryProvider(side: side, onDiskRoot: onDiskRoot)
        let docs = side == .new ? newSideDocs : oldSideDocs
        let tiers = [primary, docs, sdkProvider].compactMap { $0 }
        return try? await TieredHoverProviders(tiers).hover(query)
    }

    private func primaryProvider(side: HoverQuerySide, onDiskRoot: URL?) async -> (any HoverProvider)? {
        guard side == .new, let onDiskRoot, let lspRegistry else { return nil }
        guard let service = await lspRegistry.session(forRoot: onDiskRoot, server: .sourceKitLSP) else { return nil }
        return LanguageServerHoverProvider(service: service, resolvesDocumentationPages: true)
    }

    /// A `file://` URI under `onDiskRoot` when given, or a synthetic `atelier-blob://<oid>/<path>` URI otherwise,
    /// the shape ``HoverQuery/documentURI`` documents.
    nonisolated static func uri(path: String, blobID: String?, onDiskRoot: URL?) -> String {
        if let onDiskRoot {
            return onDiskRoot.appending(path: path).absoluteString
        }
        return "atelier-blob://\(blobID ?? "unknown")/\(path)"
    }
}

/// The documents one feed indexes: both sides of the changeset's Swift files, each answering for its own side, and
/// the corpus, the right side's other Swift files, which answer for both.
private struct HoverFeed: Sendable {
    /// A corpus file to read, and the URI it is indexed under.
    struct CorpusFile: Sendable {
        let entry: GitTreeEntry
        let uri: String
    }

    /// What a feed asks for, without the text: two feeds with the same identity index the same documents.
    struct Identity: Equatable {
        let root: URL?
        let files: [FileIdentity]
        let corpusSource: ComparisonSource?
        /// The right side's whole listing, which a feed filters for its corpus; a feed that lays the same cards out
        /// again hands over the same array, which compares without a walk.
        let corpusEntries: [GitTreeEntry]

        /// Nil when a file has a side with text but no blob id, whose text can change unseen: such a feed always runs.
        init?(
            root: URL?, files: [HoverDocumentationModel.FileEntry], corpusSource: ComparisonSource?,
            corpusEntries: [GitTreeEntry]
        ) {
            guard !files.contains(where: \.hasUnhashedSide) else { return nil }
            self.root = root
            self.files = files.map(FileIdentity.init)
            self.corpusSource = corpusSource
            self.corpusEntries = corpusEntries
        }
    }

    struct FileIdentity: Equatable {
        let leftPath: String
        let rightPath: String?
        let oldBlobID: String?
        let newBlobID: String?

        init(_ file: HoverDocumentationModel.FileEntry) {
            leftPath = file.leftPath
            rightPath = file.rightPath
            oldBlobID = file.oldBlobID
            newBlobID = file.newBlobID
        }
    }

    let changeset: [DocIndexFile]
    let corpus: [CorpusFile]
    /// Every document of the feed with the sides it answers for; the index keeps nothing else.
    let scope: [String: DocIndexSides]

    init(root: URL?, files: [HoverDocumentationModel.FileEntry], corpusEntries: [GitTreeEntry]) {
        var changeset: [String: DocIndexFile] = [:]
        func add(path: String, blobID: String?, text: String, onDiskRoot: URL?, side: DocIndexSides) {
            guard !text.isEmpty else { return }
            let uri = HoverDocumentationModel.uri(path: path, blobID: blobID, onDiskRoot: onDiskRoot)
            let sides = side.union(changeset[uri]?.sides ?? [])
            changeset[uri] = DocIndexFile(uri: uri, content: text, blobID: blobID, sides: sides)
        }
        for file in files where file.isSwift {
            add(path: file.leftPath, blobID: file.oldBlobID, text: file.oldText, onDiskRoot: nil, side: .old)
            add(
                path: file.rightPath ?? file.leftPath, blobID: file.newBlobID, text: file.newText, onDiskRoot: root,
                side: .new)
        }
        var scope = changeset.mapValues(\.sides)
        var corpus: [CorpusFile] = []
        let changed = Set(files.map { $0.rightPath ?? $0.leftPath })
        for entry in Self.corpusCandidates(entries: corpusEntries, excluding: changed) {
            let uri = HoverDocumentationModel.uri(path: entry.relativePath, blobID: entry.blobID, onDiskRoot: root)
            scope[uri] = .both
            // A document the changeset already holds is not read again.
            if changeset[uri] == nil { corpus.append(CorpusFile(entry: entry, uri: uri)) }
        }
        self.changeset = Array(changeset.values)
        self.corpus = corpus
        self.scope = scope
    }

    /// The Swift files outside the changeset within the corpus size cap, at most the corpus count cap of them.
    private static func corpusCandidates(entries: [GitTreeEntry], excluding changed: Set<String>) -> [GitTreeEntry] {
        Array(
            entries.lazy
                .filter {
                    $0.relativePath.hasSuffix(".swift") && !changed.contains($0.relativePath)
                        && $0.size <= HoverDocumentationModel.maxCorpusFileSize
                }
                .prefix(HoverDocumentationModel.maxCorpusFiles))
    }
}
