import AemiTesting
import Darwin
import KittyStyle
import KittySyntax
import KittyWorkspace
import Synchronization
import Testing

@testable import AtelierText
@testable import KittyEditor

/// The highlight pipeline on large documents: the lines on screen are highlighted from the rope at once, and the rest
/// of the document by a full pass off the main actor that installs only onto the text it read.
@Suite
@MainActor
struct EditorHighlightPipelineTests {
    private static let lineCount = 2_000
    private static let rows = 10

    nonisolated private static func line(_ index: Int) -> String {
        "let value\(index) = compute(\(index)) // note \(index)"
    }

    /// A Swift document open in a buffer and scrolled to `scrollOffset`, with a 10-row screen; `threads` records
    /// where each full pass runs.
    private func makeState(
        lines: [String] = (0 ..< lineCount).map(line), scrollOffset: Int = 1_000
    ) -> (state: EditorState, tasks: TaskProviderSpy, threads: PassThreads) {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let state = EditorState(rootPath: ".", config: KittyConfig(), taskProvider: tasks)
        state.bufferManager.open(
            filePath: "/project/large.swift", fileName: "large.swift", content: lines.joined(separator: "\n"),
            language: "swift")
        state.restoreStateFromActiveBuffer()
        state.lastRenderRows = Self.rows
        state.scrollOffset = scrollOffset
        let threads = PassThreads()
        let compute = state.fullHighlightCompute
        state.fullHighlightCompute = { input in
            threads.record()
            return await compute(input)
        }
        return (state, tasks, threads)
    }

    /// Waits, within the spy's bound, for the next full pass to be spawned and for every task to finish.
    private func awaitFullPass(_ tasks: TaskProviderSpy, after spawned: Int) async throws {
        try await tasks.waitForSpawnedTasks(atLeast: spawned + 1)
        try await tasks.waitForAllTasks()
    }

    private func styledLines(of state: EditorState) -> [Int] {
        state.highlightedLines.indices.filter { !state.highlightedLines[$0].isEmpty }
    }

    private func fullHighlight(of state: EditorState) -> [[StyledSpan]] {
        LanguageHighlighter.makeSession(language: "swift", theme: state.syntaxTheme, preferGrammar: false)
            .highlightLines(state.textBuffer.lines(in: 0 ..< state.fileLineCount))
    }

    @Test
    func `a refresh highlights the lines on screen and leaves the others without spans`() {
        let (state, _, _) = makeState()
        defer { state.shutdown() }

        state.refreshHighlights()

        #expect(state.highlightedLines.count == Self.lineCount)
        #expect(styledLines(of: state) == Array(1_000 ..< 1_030))
    }

    @Test
    func `a refresh materialises neither the document's lines nor its text`() {
        let (state, _, _) = makeState()
        defer { state.shutdown() }

        state.refreshHighlights()

        #expect(state.workspace.cachedFileLines == nil)
        #expect(state.workspace.cachedDocumentText == nil)
        #expect(state.textBuffer._testSnapshotCachesAreEmpty)
    }

    @Test
    func `a viewport highlight reads only the viewport's lines from its document`() {
        let (state, _, _) = makeState()
        defer { state.shutdown() }
        let document = RecordingDocument(TextBuffer(lines: (0 ..< 100_000).map(Self.line)))
        let session = LanguageHighlighter.makeSession(
            language: "swift", theme: state.syntaxTheme, preferGrammar: false)

        let highlights = state.highlightViewport(of: document, in: 50_000 ..< 50_030)

        #expect(document.reads.withLock { $0 } == [.lines(50_000 ..< 50_030)])
        #expect(highlights == session.highlightLines((50_000 ..< 50_030).map(Self.line)))
    }

    @Test
    func `a refresh highlights the rest of the document off the main actor`() async throws {
        let (state, tasks, threads) = makeState()
        defer { state.shutdown() }

        state.refreshHighlights()

        try await awaitFullPass(tasks, after: 0)
        #expect(threads.passes == [.background])
        #expect(state.highlightedLines == fullHighlight(of: state))
    }

    @Test
    func `the full pass styles a comment opened above the screen as one scan of the document does`() async throws {
        var lines = (0 ..< Self.lineCount).map(Self.line)
        lines[900] = "/* opened above the screen"
        lines[1_100] = "closed below it */ let tail = 1"
        let (state, tasks, _) = makeState(lines: lines)
        defer { state.shutdown() }
        let comment = state.syntaxTheme.style(for: "comment")

        state.refreshHighlights()
        try await awaitFullPass(tasks, after: 0)

        #expect(state.highlightedLines[1_000] == [StyledSpan(text: Self.line(1_000), style: comment)])
        #expect(state.highlightedLines == fullHighlight(of: state))
    }

    @Test
    func `undo highlights the lines on screen before the full pass lands`() {
        let (state, _, _) = makeState()
        defer { state.shutdown() }
        state.highlightedLines = fullHighlight(of: state)
        state.cursorRow = 1_005
        insertText("x", into: state)

        state.undoActiveBuffer()

        #expect(styledLines(of: state) == Array(1_000 ..< 1_030))
    }

    @Test
    func `undo highlights the rest of the document off the main actor`() async throws {
        let (state, tasks, threads) = makeState()
        defer { state.shutdown() }
        state.highlightedLines = fullHighlight(of: state)
        state.cursorRow = 1_005
        insertText("x", into: state)
        let spawned = tasks.spawnedTaskCount

        state.undoActiveBuffer()

        try await awaitFullPass(tasks, after: spawned)
        #expect(threads.passes == [.background])
        #expect(state.fileLine(at: 1_005) == Self.line(1_005))
        #expect(state.highlightedLines == fullHighlight(of: state))
    }

    @Test
    func `an edit that restyles past the screen hands the rest of the document to a pass off the main actor`()
        async throws
    {
        let (state, tasks, threads) = makeState(scrollOffset: 0)
        defer { state.shutdown() }
        state.highlightedLines = fullHighlight(of: state)
        let spawned = tasks.spawnedTaskCount
        let comment = state.syntaxTheme.style(for: "comment")

        insertText("/*", into: state)

        try await awaitFullPass(tasks, after: spawned)
        #expect(threads.passes == [.background])
        #expect(
            state.highlightedLines[Self.lineCount - 1]
                == [StyledSpan(text: Self.line(Self.lineCount - 1), style: comment)])
    }

    @Test
    func `an edit while the highlights are still loading highlights only the lines on screen`() {
        let (state, _, _) = makeState()
        defer { state.shutdown() }
        state.highlightedLines = []
        state.cursorRow = 1_005

        insertText("x", into: state)

        #expect(state.highlightedLines.count == Self.lineCount)
        #expect(styledLines(of: state) == Array(1_000 ..< 1_030))
    }

    @Test
    func `a pass the document outran is dropped and the current text is highlighted again`() async throws {
        let (state, tasks, _) = makeState(scrollOffset: 0)
        defer { state.shutdown() }
        state.highlightedLines = fullHighlight(of: state)
        let offScreenBeforePass = state.highlightedLines[1_900]
        // A pass over the text before the second edit waits for one gate, a pass over the edited text for the other.
        let beforeSecondEdit = TaskGate()
        let afterSecondEdit = TaskGate()
        let compute = state.fullHighlightCompute
        state.fullHighlightCompute = { input in
            try? await (input.textBuffer.line(at: 5).hasPrefix("x") ? afterSecondEdit : beforeSecondEdit).wait()
            return await compute(input)
        }
        // Opening a comment restyles past the screen, so a pass starts; typing inside the comment restyles nothing,
        // so only the outrun pass itself can ask for the next one.
        insertText("/*", into: state)
        try await tasks.waitForSpawnedTasks(atLeast: 1)
        state.cursorRow = 5
        state.cursorCol = 0
        insertText("x", into: state)

        beforeSecondEdit.open()

        try await tasks.waitForSpawnedTasks(atLeast: 2)
        #expect(state.highlightedLines[1_900] == offScreenBeforePass)
        afterSecondEdit.open()
        try await tasks.waitForAllTasks()
        #expect(state.highlightedLines == fullHighlight(of: state))
    }
}

/// The thread each full pass ran on, in order.
private final class PassThreads: Sendable {
    enum Thread: Equatable {
        case main
        case background
    }

    private let recorded = Mutex<[Thread]>([])

    var passes: [Thread] { recorded.withLock { $0 } }

    func record() {
        let thread: Thread = pthread_main_np() != 0 ? .main : .background
        recorded.withLock { $0.append(thread) }
    }
}

/// A document answering from a rope that records every read, so a test sees which lines a highlight asked for.
private final class RecordingDocument: DocumentSource {
    enum Read: Equatable {
        case lineCount
        case isEmpty
        case line(Int)
        case lines(Range<Int>)
        case serializedByteCount
        case maxLineWidth(Range<Int>)
    }

    private let buffer: TextBuffer
    let reads = Mutex<[Read]>([])

    init(_ buffer: TextBuffer) {
        self.buffer = buffer
    }

    var lineCount: Int {
        reads.withLock { $0.append(.lineCount) }
        return buffer.lineCount
    }

    var isEmpty: Bool {
        reads.withLock { $0.append(.isEmpty) }
        return buffer.isEmpty
    }

    func line(at index: Int) -> String {
        reads.withLock { $0.append(.line(index)) }
        return buffer.line(at: index)
    }

    func lines(in range: Range<Int>) -> [String] {
        reads.withLock { $0.append(.lines(range)) }
        return buffer.lines(in: range)
    }

    func serializedByteCount(lineEndingSize: Int) -> Int {
        reads.withLock { $0.append(.serializedByteCount) }
        return buffer.serializedByteCount(lineEndingSize: lineEndingSize)
    }

    func maxLineWidth(in range: Range<Int>, tabSize: Int) -> Int {
        reads.withLock { $0.append(.maxLineWidth(range)) }
        return buffer.maxLineWidth(in: range, tabSize: tabSize)
    }
}
