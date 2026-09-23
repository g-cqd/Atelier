import AemiTesting
import AtelierLSP
import AtelierSyntaxModel
import DiffGit
import Foundation
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

@MainActor
@Suite struct HoverDocumentationModelTests {
    private let swiftDocComment = """
        /// Adds two numbers.
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        """

    @Test func blobURIsAreUsedWhenThereIsNoOnDiskRoot() {
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: "abc123", onDiskRoot: nil)
        #expect(uri == "atelier-blob://abc123/Sources/Foo.swift")
    }

    @Test func blobURIsFallBackToAPlaceholderOidWithNoHash() {
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: nil, onDiskRoot: nil)
        #expect(uri == "atelier-blob://unknown/Sources/Foo.swift")
    }

    @Test func onDiskURIsAreFileURLsUnderTheRoot() {
        let root = URL(filePath: "/tmp/repo", directoryHint: .isDirectory)
        let uri = HoverDocumentationModel.uri(path: "Sources/Foo.swift", blobID: "abc123", onDiskRoot: root)
        #expect(uri == root.appending(path: "Sources/Foo.swift").absoluteString)
    }

    @Test func hoverAnswersFromTheDocCommentIndexAfterComparisonChanged() async {
        let model = HoverDocumentationModel(lspRegistry: nil)
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")
        model.comparisonChanged(root: nil, files: [entry])
        // The index update is fire-and-forget; poll briefly for it to land rather than sleeping a fixed amount.
        var content: HoverContent?
        for _ in 0 ..< 50 {
            content = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
            if content != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(content?.markdown.contains("Adds two numbers.") == true)
        #expect(content?.source == .docIndex)
    }

    // MARK: Corpus broadening

    private static let rightRoot = URL(filePath: "/right", directoryHint: .isDirectory)

    @Test func aSymbolDeclaredOutsideTheChangesetResolvesOnceTheBackgroundCorpusPassIndexesItsFile() async {
        let model = HoverDocumentationModel(lspRegistry: nil)
        let reader = FakeSourceReader()
        let restPath = "Sources/Rest.swift"
        reader.contents[restPath] = """
            /// Doubles a number.
            func double(_ x: Int) -> Int { x * 2 }
            """
        // "double" is only used here, not declared: the fast, changed-files-only pass has nothing to say about it.
        let changed = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
            oldText: "let value = double(3)\n", newText: "let value = double(3)\n", oldBlobID: "old",
            newBlobID: "new")
        let restEntry = SourceEntry(relativePath: restPath, blobID: "rest", size: 64)

        model.comparisonChanged(
            root: nil, files: [changed], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: [restEntry])

        // Both the fast and the background pass are fire-and-forget; poll briefly rather than sleeping a fixed
        // amount. "double" sits at columns 12..<18 of "let value = double(3)".
        var content: HoverContent?
        for _ in 0 ..< 100 {
            content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
            if content != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(content?.markdown.contains("Doubles a number.") == true)
    }

    @Test func theBackgroundPassNeverIndexesAFileOverTheSizeCap() async {
        let model = HoverDocumentationModel(lspRegistry: nil)
        let reader = FakeSourceReader()
        let hugePath = "Sources/Huge.swift"
        reader.contents[hugePath] = """
            /// Doubles a number.
            func double(_ x: Int) -> Int { x * 2 }
            """
        let changed = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
            oldText: "let value = double(3)\n", newText: "let value = double(3)\n", oldBlobID: "old",
            newBlobID: "new")
        let hugeEntry = SourceEntry(
            relativePath: hugePath, blobID: "huge", size: HoverDocumentationModel.maxCorpusFileSize + 1)

        model.comparisonChanged(
            root: nil, files: [changed], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: [hugeEntry])

        // Give the background pass every chance to run before asserting it never touched the oversized file.
        try? await Task.sleep(for: .milliseconds(100))
        let content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content == nil)
        try? reader.contentRequests.expectNoBufferedElements()
    }

    @Test func aStaleBackgroundPassNeverLandsAfterANewerComparisonSupersedesIt() async throws {
        let model = HoverDocumentationModel(lspRegistry: nil)
        let reader = FakeSourceReader()
        let restPath = "Sources/Rest.swift"
        let gate = AsyncProbe<Void>()
        reader.gate[restPath] = gate
        reader.contents[restPath] = """
            /// Doubles a number.
            func double(_ x: Int) -> Int { x * 2 }
            """
        let restEntry = SourceEntry(relativePath: restPath, blobID: "rest", size: 64)
        let firstChanged = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift",
            oldText: "let value = double(3)\n", newText: "let value = double(3)\n", oldBlobID: "old",
            newBlobID: "new")

        model.comparisonChanged(
            root: nil, files: [firstChanged], corpusReader: reader, corpusSource: .directory(Self.rightRoot),
            corpusEntries: [restEntry])
        // Waits until the stale pass blocks on its corpus read, so the newer comparison supersedes it mid-flight.
        _ = try await reader.contentRequests.next()

        let secondChanged = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: "let x = 1\n",
            newText: "let x = 1\n", oldBlobID: "old2", newBlobID: "new2")
        model.comparisonChanged(root: nil, files: [secondChanged])
        // The stale read resolves only now, when landing would clobber the newer comparison's corpus.
        gate.send(())

        // Give the stale pass every chance to land wrongly before asserting it never did.
        try? await Task.sleep(for: .milliseconds(100))
        let content = await model.hover(fileIndex: 0, side: .new, line: 0, utf16Column: 13)
        #expect(content == nil)
    }

    @Test func theOldSideNeverConsultsTheLanguageServer() async {
        let callCount = Locked(0)
        let registry = SourceKitLSPRegistry { _ in
            callCount.increment()
            return nil
        }
        let model = HoverDocumentationModel(lspRegistry: registry)
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")
        let root = URL(filePath: "/tmp/repo", directoryHint: .isDirectory)
        model.comparisonChanged(root: root, files: [entry])
        _ = await model.hover(fileIndex: 0, side: .old, line: 1, utf16Column: 6)
        #expect(callCount.value == 0)
    }

    @Test func theNewSideOnDiskConsultsTheLanguageServerRegistry() async {
        let callCount = Locked(0)
        let registry = SourceKitLSPRegistry { _ in
            callCount.increment()
            return nil
        }
        let model = HoverDocumentationModel(lspRegistry: registry)
        let entry = HoverDocumentationModel.FileEntry(
            index: 0, leftPath: "Sources/Foo.swift", rightPath: "Sources/Foo.swift", oldText: swiftDocComment,
            newText: swiftDocComment, oldBlobID: "old", newBlobID: "new")
        let root = URL(filePath: "/tmp/repo", directoryHint: .isDirectory)
        model.comparisonChanged(root: root, files: [entry])
        _ = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
        #expect(callCount.value == 1)
    }
}

/// A tiny lock-protected counter, since these tests run their closures from an actor's isolated context.
private final class Locked: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int

    init(_ value: Int) {
        storage = value
    }

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
