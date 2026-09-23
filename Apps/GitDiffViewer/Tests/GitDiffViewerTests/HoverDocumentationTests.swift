import AemiTesting
import AtelierLSP
import AtelierSyntaxModel
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

private struct StubHoverProvider: HoverProvider {
    enum Outcome {
        case content(String)
        case none
        case failure(any Error)
        case cancelled
    }

    let outcome: Outcome
    let onCalled: (@Sendable () -> Void)?

    init(_ outcome: Outcome, onCalled: (@Sendable () -> Void)? = nil) {
        self.outcome = outcome
        self.onCalled = onCalled
    }

    func hover(_ query: HoverQuery) async throws -> HoverContent? {
        onCalled?()
        switch outcome {
            case .content(let markdown): return HoverContent(markdown: markdown, source: .docIndex)
            case .none: return nil
            case .failure(let error): throw error
            case .cancelled: throw CancellationError()
        }
    }
}

private struct StubError: Error {}

private func query(line: Int = 0, column: Int = 0) -> HoverQuery {
    HoverQuery(documentURI: "file:///tmp/example.swift", content: "let x = 1\n", line: line, utf16Column: column)
}

@Suite struct TieredHoverProviderTests {
    @Test func primaryWinsWhenItAnswers() async throws {
        let provider = TieredHoverProvider(
            primary: StubHoverProvider(.content("primary")), fallback: StubHoverProvider(.content("fallback")))
        let content = try await provider.hover(query())
        #expect(content?.markdown == "primary")
    }

    @Test func nilPrimaryFallsBackToTheDocIndex() async throws {
        let provider = TieredHoverProvider(
            primary: StubHoverProvider(.none), fallback: StubHoverProvider(.content("fallback")))
        let content = try await provider.hover(query())
        #expect(content?.markdown == "fallback")
    }

    @Test func throwingPrimaryFallsBackToTheDocIndex() async throws {
        let provider = TieredHoverProvider(
            primary: StubHoverProvider(.failure(StubError())), fallback: StubHoverProvider(.content("fallback")))
        let content = try await provider.hover(query())
        #expect(content?.markdown == "fallback")
    }

    @Test func noPrimaryGoesStraightToTheDocIndex() async throws {
        let provider = TieredHoverProvider(primary: nil, fallback: StubHoverProvider(.content("fallback")))
        let content = try await provider.hover(query())
        #expect(content?.markdown == "fallback")
    }

    @Test func cancellationFromThePrimaryPropagatesRatherThanFallingBack() async throws {
        let provider = TieredHoverProvider(
            primary: StubHoverProvider(.cancelled), fallback: StubHoverProvider(.content("fallback")))
        await #expect(throws: CancellationError.self) {
            try await provider.hover(query())
        }
    }
}

/// Serves the corpus pass from memory, recording each batch it asks for; a held batch waits for its gate.
private final class CorpusReaderSpy: SourceReading, Sendable {
    private struct State {
        var contents: [String: String] = [:]
        var batches: [[String]] = []
        var hold: TaskGate?
    }

    private let state = Mutex(State())
    /// Each batch's paths as its read starts.
    let batchStarted = AsyncProbe<[String]>()

    /// Every batch read so far, in order.
    var batches: [[String]] { state.withLock(\.batches) }

    subscript(path: String) -> String? {
        get { state.withLock { $0.contents[path] } }
        set { state.withLock { $0.contents[path] = newValue } }
    }

    /// Holds every later batch inside its read until `gate` opens.
    func hold(until gate: TaskGate) {
        state.withLock { $0.hold = gate }
    }

    func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String] {
        let paths = entries.map(\.relativePath)
        let hold = state.withLock { state in
            state.batches.append(paths)
            return state.hold
        }
        batchStarted.send(paths)
        if let hold { try await hold.wait() }
        let contents = state.withLock(\.contents)
        return Dictionary(uniqueKeysWithValues: paths.compactMap { path in contents[path].map { (path, $0) } })
    }

    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        try await contents(of: [entry], in: source)[entry.relativePath] ?? ""
    }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? { nil }

    func entries(of source: ComparisonSource) async throws -> [SourceEntry] { [] }

    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] { [:] }
}

@MainActor
@Suite struct HoverDocumentationModelTests {
    private let swiftDocComment = """
        /// Adds two numbers.
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        """
    private static let rightRoot = URL(filePath: "/right", directoryHint: .isDirectory)
    private static let restPath = "Sources/Rest.swift"
    private static let restSource = """
        /// Doubles a number.
        func double(_ x: Int) -> Int { x * 2 }
        """

    private let taskProvider = TaskProviderSpy.tolerant()

    private func makeSUT(lspRegistry: SourceKitLSPRegistry? = nil) -> HoverDocumentationModel {
        HoverDocumentationModel(lspRegistry: lspRegistry, taskProvider: taskProvider)
    }

    /// A changed file that only calls `double`, which ``restSource`` declares; "double" sits at columns 12..<18.
    private func caller(index: Int = 0, blob: String = "new") -> HoverDocumentationModel.FileEntry {
        HoverDocumentationModel.FileEntry(
            index: index, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
            oldText: "let value = double(3)\n", newText: "let value = double(3)\n", oldBlobID: "old", newBlobID: blob)
    }

    private func restEntry(blob: String = "rest") -> SourceEntry {
        SourceEntry(relativePath: Self.restPath, blobID: blob, size: 64)
    }

    /// A reader holding ``restSource`` at ``restPath``.
    private func makeReader() -> CorpusReaderSpy {
        let reader = CorpusReaderSpy()
        reader[Self.restPath] = Self.restSource
        return reader
    }

    /// Feeds `files` with the corpus `entries` of `reader`, then waits for every pass to land.
    private func feed(
        _ model: HoverDocumentationModel, _ files: [HoverDocumentationModel.FileEntry], root: URL? = nil,
        reader: CorpusReaderSpy? = nil, corpus entries: [SourceEntry] = []
    ) async throws {
        let source: ComparisonSource? = reader == nil ? nil : .directory(Self.rightRoot)
        model.comparisonChanged(
            root: root, files: files, corpusReader: reader, corpusSource: source, corpusEntries: entries)
        try await taskProvider.waitForAllTasks()
    }

    @Test
    func `blob URIs are used when there is no on-disk root`() {
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: "abc123", onDiskRoot: nil)
        #expect(uri == "atelier-blob://abc123/Sources/Foo.swift")
    }

    @Test
    func `blob URIs fall back to a placeholder id with no hash`() {
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: nil, onDiskRoot: nil)
        #expect(uri == "atelier-blob://unknown/Sources/Foo.swift")
    }

    @Test
    func `on-disk URIs are file URLs under the root`() {
        let root = URL(filePath: "/tmp/repo", directoryHint: .isDirectory)
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: "abc123", onDiskRoot: root)
        #expect(uri == root.appending(path: "Sources/Foo.swift").absoluteString)
    }

    @Test
    func `a hover answers from the doc comment index once the comparison is fed`() async throws {
        let model = makeSUT()
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")

        try await feed(model, [entry])

        let content = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
        #expect(content?.markdown.contains("Adds two numbers.") == true)
        #expect(content?.source == .docIndex)
    }

    // MARK: Corpus

    @Test
    func `a symbol declared outside the changeset resolves once the corpus pass indexes its file`() async throws {
        let model = makeSUT()

        try await feed(model, [caller()], reader: makeReader(), corpus: [restEntry()])

        let content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content?.markdown.contains("Doubles a number.") == true)
    }

    @Test
    func `the corpus pass never reads a file over the size cap`() async throws {
        let model = makeSUT()
        let reader = makeReader()
        let huge = SourceEntry(
            relativePath: Self.restPath, blobID: "huge", size: HoverDocumentationModel.maxCorpusFileSize + 1)

        try await feed(model, [caller()], reader: reader, corpus: [huge])

        #expect(await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13) == nil)
        #expect(reader.batches.isEmpty)
    }

    @Test
    func `a stale corpus pass never lands after a newer comparison supersedes it`() async throws {
        let model = makeSUT()
        let reader = makeReader()
        let gate = TaskGate()
        reader.hold(until: gate)

        model.comparisonChanged(
            root: nil, files: [caller()], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: [restEntry()])
        // The stale pass is inside its corpus read when the newer comparison supersedes it.
        _ = try await reader.batchStarted.next()
        let unrelated = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: "let x = 1\n",
            newText: "let x = 1\n", oldBlobID: "old2", newBlobID: "new2")
        model.comparisonChanged(root: nil, files: [unrelated])
        // The stale read resolves only now, when landing would clobber the newer comparison's corpus.
        gate.open()
        try await taskProvider.waitForAllTasks()

        #expect(await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13) == nil)
    }

    // MARK: Language server tier

    @Test
    func `the old side never consults the language server`() async throws {
        let callCount = Mutex(0)
        let registry = SourceKitLSPRegistry(
            admits: { _ in true },
            makeConfiguration: { _ in
                callCount.withLock { $0 += 1 }
                return nil
            })
        let model = makeSUT(lspRegistry: registry)
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")
        let root = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        model.comparisonChanged(root: root, files: [entry])
        _ = await model.hover(fileIndex: 0, side: .old, line: 1, utf16Column: 6)
        #expect(callCount.withLock { $0 } == 0)
    }

    @Test
    func `the new side on disk consults the language server registry`() async throws {
        let callCount = Mutex(0)
        let registry = SourceKitLSPRegistry(
            admits: { _ in true },
            makeConfiguration: { _ in
                callCount.withLock { $0 += 1 }
                return nil
            })
        let model = makeSUT(lspRegistry: registry)
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")
        let root = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        model.comparisonChanged(root: root, files: [entry])
        _ = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
        #expect(callCount.withLock { $0 } == 1)
    }

    /// A fresh directory standing in for a repository root, since the registry only admits roots that exist.
    private func makeScratchRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-hover-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
