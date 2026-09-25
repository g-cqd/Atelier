import AemiCore
import AemiTesting
import Foundation
import KittyStyle
import KittySyntax
import Synchronization
import Testing

@testable import AtelierText
@testable import KittyEditor
@testable import KittyWorkspace

/// A document whose grammar qualifies (its artifacts load and its parse passes the quality gate) keeps its grammar
/// color through refreshes and edits: an edit re-colors only its own lines with the lexer, and the reparse that
/// follows a pause brings the grammar back. A document that fails the gate stays lexical (book D36).
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EditorGrammarColorTests {
    private static let rows = 10

    /// A JSON object of 180 keys in groups of nine, each after a comment line, which the grammar colors as a comment
    /// and the lexer leaves plain. Line 11 is a comment.
    private static let clean =
        "{\n"
        + (0 ..< 200).map { $0 % 10 == 0 ? "  // group \($0 / 10)" : "  \"key\($0)\": \($0)," }
        .joined(separator: "\n") + "\n  \"last\": true\n}"
    private static let editedRow = 11
    /// Swift in a JSON file: most of each line lies under ERROR nodes, so the parse fails the quality gate.
    private static let broken = (0 ..< 200)
        .map { #"{"key\#($0)": if let value = compute() { return value * 2 } else { return nil }}"# }
        .joined(separator: "\n")

    @MainActor
    private struct Fixture {
        let state: EditorState
        let tasks: TaskProviderSpy
        let clock: TestClock
        let root: URL
        let passes: PassCounter

        func tearDown() {
            state.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "kitty-grammar-color-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let clock = TestClock()
        let state = EditorState(
            rootPath: root.path, config: KittyConfig(), taskProvider: tasks, clock: clock,
            searchPool: EditorTestPool.shared)
        state.lastRenderRows = Self.rows
        let passes = PassCounter()
        let compute = state.fullHighlightCompute
        state.fullHighlightCompute = { input in
            passes.record()
            return await compute(input)
        }
        return Fixture(state: state, tasks: tasks, clock: clock, root: root, passes: passes)
    }

    /// Opens `text` as a JSON file through the open path and waits for its post-open pass.
    private func open(_ text: String, in fixture: Fixture) async throws {
        try await fixture.tasks.waitForAllTasks()
        fixture.state.finishOpeningFile(
            requestID: fixture.state.nextOpenRequestID(), path: fixture.root.appending(path: "data.json").path,
            name: "data.json", loadedFile: try WorkspaceFileLoading.decode(Data(text.utf8)), language: "json",
            modificationDate: nil)
        try await fixture.tasks.waitForAllTasks()
    }

    /// Waits for the next full pass to be spawned and for every task to finish.
    private func awaitFullPass(_ tasks: TaskProviderSpy, after spawned: Int) async throws {
        try await tasks.waitForSpawnedTasks(atLeast: spawned + 1)
        try await tasks.waitForAllTasks()
    }

    private func grammarLines(of state: EditorState) -> LineHighlights {
        LineHighlights(
            LanguageHighlighter.makeSession(language: "json", theme: state.syntaxTheme)
                .highlightDocument(source: state.textBuffer.text))
    }

    private func lexicalLines(of state: EditorState) -> LineHighlights {
        LineHighlights(
            LanguageHighlighter.makeSession(language: "json", theme: state.syntaxTheme, preferGrammar: false)
                .highlightDocument(source: state.textBuffer.text))
    }

    private func lexicalLine(_ index: Int, of state: EditorState) -> [StyledSpan] {
        LanguageHighlighter.makeSession(language: "json", theme: state.syntaxTheme, preferGrammar: false)
            .highlightLines([state.fileLine(at: index)])[0]
    }

    @Test
    func `a refresh keeps the grammar's color on screen and in the pass that follows`() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let state = fixture.state
        try await open(Self.clean, in: fixture)
        let grammar = grammarLines(of: state)
        try #require(grammar != lexicalLines(of: state))
        try #require(state.highlightedLines == grammar)
        let onScreen = 0 ..< Self.rows
        let spawned = fixture.tasks.spawnedTaskCount

        state.refreshHighlights()

        #expect(Array(state.highlightedLines[onScreen]) == Array(grammar[onScreen]))
        try await awaitFullPass(fixture.tasks, after: spawned)
        #expect(state.highlightedLines == grammar)
    }

    @Test
    func `an edit re-colors only its line with the lexer until the reparse brings the grammar back`() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let state = fixture.state
        try await open(Self.clean, in: fixture)
        let before = state.highlightedLines
        state.cursorRow = Self.editedRow
        state.cursorCol = 5

        insertText("x", into: state)

        try #require(state.fileLine(at: Self.editedRow) == "  // xgroup 1")
        try #require(state.highlightedLines[Self.editedRow] == lexicalLine(Self.editedRow, of: state))
        let untouched = state.highlightedLines.indices.filter { $0 != Self.editedRow }
        try #require(untouched.allSatisfy { state.highlightedLines[$0] == before[$0] })
        try await fixture.clock.waitForSleepers(count: 1)
        let spawned = fixture.tasks.spawnedTaskCount
        fixture.clock.advance(by: .milliseconds(150))
        try await awaitFullPass(fixture.tasks, after: spawned)
        #expect(state.highlightedLines == grammarLines(of: state))
        #expect(state.highlightedLines[Self.editedRow] != lexicalLine(Self.editedRow, of: state))
    }

    @Test
    func `the reparse waits for a pause of 150 ms after the last keystroke`() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let state = fixture.state
        try await open(Self.clean, in: fixture)
        state.cursorRow = Self.editedRow
        state.cursorCol = 5
        let passesBefore = fixture.passes.count

        insertText("x", into: state)
        try await fixture.clock.waitForSleepers(count: 1)
        fixture.clock.advance(by: .milliseconds(100))
        let mark = fixture.clock.registrationMark()
        insertText("y", into: state)
        try await fixture.clock.waitForSleepers(1, after: mark)
        // 200 ms after the first keystroke, 100 ms after the second: the first's reparse was cancelled.
        fixture.clock.advance(by: .milliseconds(100))
        let spawned = fixture.tasks.spawnedTaskCount
        fixture.clock.advance(by: .milliseconds(50))
        try await awaitFullPass(fixture.tasks, after: spawned)

        #expect(fixture.passes.count == passesBefore + 1)
        #expect(state.highlightedLines == grammarLines(of: state))
    }

    @Test
    func `a document that fails the quality gate stays lexical`() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let state = fixture.state
        try await open(Self.broken, in: fixture)
        try #require(grammarLines(of: state) == lexicalLines(of: state))
        #expect(state.highlightedLines == lexicalLines(of: state))
        let spawned = fixture.tasks.spawnedTaskCount

        state.refreshHighlights()
        try await awaitFullPass(fixture.tasks, after: spawned)

        #expect(state.highlightedLines == lexicalLines(of: state))
    }
}

/// The number of full passes run.
private final class PassCounter: Sendable {
    private let recorded = Mutex(0)

    var count: Int { recorded.withLock { $0 } }

    func record() {
        recorded.withLock { $0 += 1 }
    }
}
