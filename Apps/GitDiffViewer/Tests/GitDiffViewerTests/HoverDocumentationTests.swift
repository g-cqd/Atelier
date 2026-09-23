import AemiTesting
import AtelierDocIndex
import AtelierLSP
import AtelierSyntaxModel
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

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

    /// How many times `path` was read.
    func reads(of path: String) -> Int {
        state.withLock { $0.batches.joined().filter { $0 == path }.count }
    }

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

/// Counts the files an index parses.
private final class ParseCounter: Sendable {
    private let parsed = Mutex(0)

    var count: Int { parsed.withLock { $0 } }

    func extract(uri: String, content: String) -> [DocEntry] {
        parsed.withLock { $0 += 1 }
        return DocCommentIndex.extractEntries(uri: uri, content: content)
    }
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
    private let parses = ParseCounter()

    private func makeSUT(
        lspRegistry: SourceKitLSPRegistry? = nil, index: DocCommentIndex = DocCommentIndex()
    ) -> HoverDocumentationModel {
        HoverDocumentationModel(lspRegistry: lspRegistry, taskProvider: taskProvider, index: index)
    }

    /// An index that counts the files it parses in ``parses``.
    private func countingIndex() -> DocCommentIndex {
        DocCommentIndex(extractor: { [parses] uri, content in parses.extract(uri: uri, content: content) })
    }

    /// A changed file that only calls `double`, which ``restSource`` declares; "double" sits at columns 12..<18.
    private func caller(blob: String = "new") -> HoverDocumentationModel.FileEntry {
        HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
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
        _ = try await reader.batchStarted.expectNext()
        let unrelated = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: "let x = 1\n",
            newText: "let x = 1\n", oldBlobID: "old2", newBlobID: "new2")
        model.comparisonChanged(root: nil, files: [unrelated])
        // The stale read resolves only now, when landing would clobber the newer comparison's corpus.
        gate.open()
        try await taskProvider.waitForAllTasks()

        #expect(await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13) == nil)
    }

    @Test
    func `a superseded corpus pass asks for no further batch`() async throws {
        let model = makeSUT()
        let reader = makeReader()
        let gate = TaskGate()
        reader.hold(until: gate)
        let corpus = (0 ..< HoverDocumentationModel.corpusChunkSize + 8)
            .map { SourceEntry(relativePath: "Sources/F\($0).swift", blobID: "f\($0)", size: 64) }

        model.comparisonChanged(
            root: nil, files: [caller()], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: corpus)
        let first = try #require(try await reader.batchStarted.expectNext())
        model.comparisonChanged(root: nil, files: [caller(blob: "newer")])
        gate.open()
        try await taskProvider.waitForAllTasks()

        #expect(first.count < corpus.count)
        #expect(reader.batches == [first])
    }

    @Test
    func `an identical feed reads no corpus file again`() async throws {
        let model = makeSUT()
        let reader = makeReader()

        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])
        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])

        #expect(reader.reads(of: Self.restPath) == 1)
    }

    @Test
    func `an identical feed parses nothing`() async throws {
        let model = makeSUT(index: countingIndex())
        let reader = makeReader()
        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])
        let parsed = parses.count

        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])

        #expect(parsed == 3)
        #expect(parses.count == parsed)
    }

    @Test
    func `a feed with no files leaves the corpus indexed for the next feed`() async throws {
        let model = makeSUT()
        let reader = makeReader()

        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])
        try await feed(model, [])
        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])

        #expect(reader.reads(of: Self.restPath) == 1)
        let content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content?.markdown.contains("Doubles a number.") == true)
    }

    @Test
    func `growing the changeset keeps the corpus indexed`() async throws {
        let model = makeSUT()
        let reader = makeReader()
        let second = HoverDocumentationModel.FileEntry(
            index: 1, leftPath: "Sources/Bar.swift", rightPath: "Sources/Bar.swift", oldText: "let x = 1\n",
            newText: "let x = 2\n", oldBlobID: "bar1", newBlobID: "bar2")

        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])
        try await feed(model, [caller(), second], reader: reader, corpus: [restEntry()])

        #expect(reader.reads(of: Self.restPath) == 1)
        let content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content?.markdown.contains("Doubles a number.") == true)
    }

    @Test
    func `a file without a blob id is fed again`() async throws {
        let model = makeSUT()
        func unhashed(_ doc: String) -> HoverDocumentationModel.FileEntry {
            let text = "/// \(doc)\nfunc run() {}\n"
            return HoverDocumentationModel.FileEntry(
                index: 0, leftPath: "Sources/Big.swift", rightPath: "Sources/Big.swift", oldText: text,
                newText: text, oldBlobID: "big", newBlobID: nil)
        }

        try await feed(model, [unhashed("One.")])
        try await feed(model, [unhashed("Two.")])

        let content = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
        #expect(content?.markdown.contains("Two.") == true)
    }

    @Test
    func `the index holds only the current comparison over twenty comparisons`() async throws {
        let index = DocCommentIndex()
        let model = makeSUT(index: index)
        let reader = makeReader()
        var sizes: [Int] = []

        for comparison in 0 ..< 20 {
            let changed = HoverDocumentationModel.FileEntry(
                index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
                oldText: "let value = double(\(comparison))\n", newText: "let value = double(3)\n",
                oldBlobID: "old\(comparison)", newBlobID: "new\(comparison)")
            try await feed(model, [changed], reader: reader, corpus: [restEntry(blob: "rest\(comparison)")])
            sizes.append(await index.fileCount)
        }

        // Each comparison is one changed file's two sides and one corpus file.
        #expect(sizes == Array(repeating: 3, count: 20))
    }

    @Test
    func `a corpus file renamed on disk leaves nothing under its old path`() async throws {
        let model = makeSUT()
        let reader = CorpusReaderSpy()
        reader["Sources/Old.swift"] = "/// Doubles, as it was.\nfunc double(_ x: Int) -> Int { x * 2 }\n"
        reader["Sources/New.swift"] = "/// Doubles, as it is.\nfunc double(_ x: Int) -> Int { x * 2 }\n"
        let root = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try await feed(
            model, [caller()], root: root, reader: reader,
            corpus: [SourceEntry(relativePath: "Sources/Old.swift", blobID: "d1", size: 64)])
        try await feed(
            model, [caller()], root: root, reader: reader,
            corpus: [SourceEntry(relativePath: "Sources/New.swift", blobID: "d2", size: 64)])

        let markdown = try #require(await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)?.markdown)
        #expect(markdown.contains("as it is."))
        #expect(!markdown.contains("as it was."))
    }

    @Test
    func `a model turned off reads and parses nothing`() async throws {
        let index = countingIndex()
        let model = makeSUT(index: index)
        let reader = makeReader()
        model.isEnabled = false

        try await feed(model, [caller()], reader: reader, corpus: [restEntry()])

        #expect(reader.batches.isEmpty)
        #expect(parses.count == 0)
        #expect(await index.fileCount == 0)
    }

    @Test
    func `turning the model off stops the corpus pass in flight`() async throws {
        let model = makeSUT()
        let reader = makeReader()
        let gate = TaskGate()
        reader.hold(until: gate)
        let corpus = (0 ..< HoverDocumentationModel.corpusChunkSize + 8)
            .map { SourceEntry(relativePath: "Sources/F\($0).swift", blobID: "f\($0)", size: 64) }

        model.comparisonChanged(
            root: nil, files: [caller()], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: corpus)
        let first = try #require(try await reader.batchStarted.expectNext())
        model.isEnabled = false
        gate.open()
        try await taskProvider.waitForAllTasks()

        #expect(reader.batches == [first])
    }

    /// A fresh directory standing in for a repository root, since the registry only admits roots that exist.
    private func makeScratchRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-hover-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

extension HoverDocumentationModelTests {
    // MARK: One declaration per side (HOVER-11)

    /// `Foo`, declared in a file whose new side adds a conformance, and a second file that uses it; "Foo" sits at
    /// columns 10..<13 of "let foo = Foo()".
    private func declarationAndUse(leftPath: String, rightPath: String) -> [HoverDocumentationModel.FileEntry] {
        [
            HoverDocumentationModel.FileEntry(
                index: 0, leftPath: leftPath, rightPath: rightPath, oldText: "/// A foo.\nstruct Foo {}\n",
                newText: "/// A foo.\nstruct Foo: Sendable {}\n", oldBlobID: "foo1", newBlobID: "foo2"),
            HoverDocumentationModel.FileEntry(
                index: 1, leftPath: "Sources/Use.swift", rightPath: "Sources/Use.swift",
                oldText: "let foo = Foo()\n", newText: "let foo = Foo()\n", oldBlobID: "use1", newBlobID: "use2")
        ]
    }

    @Test
    func `hovering the new side of two refs lists only the new declaration`() async throws {
        let model = makeSUT()
        try await feed(model, declarationAndUse(leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift"))

        let markdown = try #require(await model.hover(fileIndex: 1, side: .new, line: 0, utf16Column: 11)?.markdown)

        #expect(markdown.contains("```swift\nstruct Foo: Sendable\n```"))
        #expect(!markdown.contains("```swift\nstruct Foo\n```"))
    }

    @Test
    func `hovering the old side of two refs lists only the old declaration`() async throws {
        let model = makeSUT()
        try await feed(model, declarationAndUse(leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift"))

        let markdown = try #require(await model.hover(fileIndex: 1, side: .old, line: 0, utf16Column: 11)?.markdown)

        #expect(markdown.contains("```swift\nstruct Foo\n```"))
        #expect(!markdown.contains("Sendable"))
    }

    @Test
    func `hovering the new side of a renamed file lists only its new declaration`() async throws {
        let model = makeSUT()
        let root = try makeScratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await feed(model, declarationAndUse(leftPath: "Old/Foo.swift", rightPath: "New/Foo.swift"), root: root)

        let markdown = try #require(await model.hover(fileIndex: 1, side: .new, line: 0, utf16Column: 11)?.markdown)

        #expect(markdown.contains("```swift\nstruct Foo: Sendable\n```"))
        #expect(!markdown.contains("```swift\nstruct Foo\n```"))
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
}
