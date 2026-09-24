import AemiCore
import AemiTesting
import AtelierText
import Foundation
import KittyRenderer
import KittyStyle
import KittySyntax
import KittyTerminal
import Testing

import func AemiTestKit.mallocDelta

@testable import KittyEditor
@testable import KittyWorkspace

/// Release timings of the editor's main-actor work on a million-line Swift-like file, printed rather than asserted:
/// `GDV_BENCH=1 swift test -c release --filter EditorLargeFileBenchmark`. The one assertion counts allocations, and the
/// counter is process-wide, so run the suite alone.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
@MainActor
struct EditorLargeFileBenchmark {
    private static let lineCount = 1_000_000
    private static let lines: [String] = (0 ..< lineCount).map(swiftLikeLine)
    private static let text = lines.joined(separator: "\n")

    /// Doc comments, declarations, strings, a block comment and a blank line, cycling so every run reads the same text.
    nonisolated private static func swiftLikeLine(_ index: Int) -> String {
        switch index % 8 {
            case 0: "/// Returns the value for item \(index), clamped to the table."
            case 1: "public func compute\(index)(index: Int, name: String) -> Int {"
            case 2: "    let value = index &* \(index % 97) + name.utf8.count  // trailing note"
            case 3: "    guard value > 0 else { return 0 }"
            case 4: "    /* scratch \(index) */ let label = \"item \\(index) of \(index)\""
            case 5: "    return value + label.count"
            case 6: "}"
            default: ""
        }
    }

    private static func summary(_ samples: [Duration]) -> String {
        let milliseconds =
            samples.map {
                Double($0.components.seconds) * 1_000 + Double($0.components.attoseconds) / 1e15
            }
            .sorted()
        return String(
            format: "median %.4f ms, p10 %.4f, p90 %.4f, n %d", milliseconds[milliseconds.count / 2],
            milliseconds[milliseconds.count / 10], milliseconds[milliseconds.count * 9 / 10], milliseconds.count)
    }

    /// The document open in a buffer, fully highlighted and measured, with the cursor and a 60-row screen halfway down.
    private func makeHighlightedState(taskProvider: any TaskProvider = .default) -> EditorState {
        let state = EditorState(rootPath: ".", config: KittyConfig(), taskProvider: taskProvider)
        state.bufferManager.open(
            filePath: "/bench/large.swift", fileName: "large.swift", content: Self.text, language: "swift")
        state.restoreStateFromActiveBuffer()
        state.lastRenderRows = 60
        state.cursorRow = 500_000
        state.cursorCol = 4
        state.scrollOffset = 499_980
        let session = LanguageHighlighter.makeSession(language: "swift", theme: state.syntaxTheme, preferGrammar: false)
        state.highlightedLines = session.highlightLines(Self.lines)
        state.cachedMaxLineWidth = TextDocument.computeMaxLineWidth(for: Self.lines)
        return state
    }

    @Test func `a keystroke in the middle of a million-line file`() {
        let state = makeHighlightedState()
        defer { state.shutdown() }
        for _ in 0 ..< 5 { insertText("x", into: state) }
        let clock = ContinuousClock()
        let samples = (0 ..< 31).map { _ in clock.measure { insertText("x", into: state) } }
        let edited = [StyledSpan(text: "edited", style: .default)]
        state.highlightedLines.replaceSubrange(10 ..< 11, with: [edited])
        let allocations = mallocDelta { state.highlightedLines.replaceSubrange(10 ..< 11, with: [edited]) }
        print(
            "BENCH keystroke, 1M lines: \(Self.summary(samples)); one replaceSubrange through the state: "
                + "\(allocations.map { "\($0) allocations" } ?? "not counted")")
        if let allocations { #expect(allocations == 0) }
    }

    /// Lets the full pass the last action asked for land, so it never runs during the next timed sample.
    private func awaitFullPass(_ tasks: TaskProviderSpy, after spawned: Int) async throws {
        try await tasks.waitForSpawnedTasks(atLeast: spawned + 1)
        try await tasks.waitForAllTasks()
    }

    @Test func `refreshing the highlights of a million-line file`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
        let state = makeHighlightedState(taskProvider: tasks)
        defer { state.shutdown() }
        let clock = ContinuousClock()
        var refresh: [Duration] = []
        for _ in 0 ..< 5 {
            let spawned = tasks.spawnedTaskCount
            refresh.append(clock.measure { state.refreshHighlights() })
            try await awaitFullPass(tasks, after: spawned)
        }
        let onScreen = 499_980 ..< 500_040
        let viewport = (0 ..< 31)
            .map { _ in
                clock.measure { _ = state.highlightViewport(of: state.textBuffer, in: onScreen) }
            }
        print("BENCH refreshHighlights, 1M lines: \(Self.summary(refresh))")
        print("BENCH viewport highlight of 60 lines, 1M lines: \(Self.summary(viewport))")
    }

    @Test func `undoing and redoing a keystroke in a million-line file`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
        let state = makeHighlightedState(taskProvider: tasks)
        defer { state.shutdown() }
        insertText("x", into: state)
        let clock = ContinuousClock()
        var undo: [Duration] = []
        var redo: [Duration] = []
        for _ in 0 ..< 5 {
            var spawned = tasks.spawnedTaskCount
            undo.append(clock.measure { state.undoActiveBuffer() })
            try await awaitFullPass(tasks, after: spawned)
            spawned = tasks.spawnedTaskCount
            redo.append(clock.measure { state.redoActiveBuffer() })
            try await awaitFullPass(tasks, after: spawned)
        }
        print("BENCH undo, 1M lines: \(Self.summary(undo))")
        print("BENCH redo, 1M lines: \(Self.summary(redo))")
    }

    /// The main actor's share of an open once the read has finished, which built the rope: installing the file, then
    /// the first frame.
    @Test func `opening a million-line file`() async throws {
        let loadedFile = try WorkspaceFileLoading.decode(Data(Self.text.utf8))
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 5 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = EditorState(rootPath: ".", config: KittyConfig(), taskProvider: tasks)
            let pipeline = RenderPipeline(
                connection: MockTerminalConnection(size: TerminalSize(columns: 200, rows: 60)), columns: 200, rows: 60)
            let requestID = state.nextOpenRequestID()
            samples.append(
                clock.measure {
                    state.finishOpeningFile(
                        requestID: requestID, path: "/bench/large.swift", name: "large.swift", loadedFile: loadedFile,
                        language: "swift", modificationDate: nil)
                    renderFrame(pipeline: pipeline, state: state)
                })
            // The post-load pass lands before the next sample.
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH open to first frame, main actor, 1M lines: \(Self.summary(samples))")
    }

    /// The document as an open leaves it: highlighted by a full pass, whose lines the buffer and the screen share.
    private func makeOpenedState(tasks: TaskProviderSpy) async throws -> EditorState {
        let state = EditorState(rootPath: ".", config: KittyConfig(), taskProvider: tasks)
        let spawned = tasks.spawnedTaskCount
        state.bufferManager.open(
            filePath: "/bench/large.swift", fileName: "large.swift", content: Self.text, language: "swift")
        state.lastRenderRows = 60
        state.restoreStateFromActiveBuffer()
        try await awaitFullPass(tasks, after: spawned)
        state.saveStateToActiveBuffer()
        return state
    }

    /// The main actor's share of closing the only tab, which lets go of the document's rope and its highlights.
    @Test func `closing the last tab of a million-line file`() async throws {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = try await makeOpenedState(tasks: tasks)
            samples.append(clock.measure { state.closeCurrentTab() })
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH close the last tab, main actor, 1M lines: \(Self.summary(samples))")
    }

    /// The main actor's share of reloading a changed file once its read has finished: the reload's undo step, then
    /// installing the new text in place of the old text's highlights.
    @Test func `reloading a changed million-line file`() async throws {
        let changed = try WorkspaceFileLoading.decode(Data((Self.text + "\n// changed on disk").utf8))
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = try await makeOpenedState(tasks: tasks)
            let buffer = try #require(state.bufferManager.activeBuffer)
            samples.append(
                try await clock.measure {
                    let reloaded = try await buffer.reloadFromDisk(offloadFileRead: { _ in changed }) {
                        state.saveStateToActiveBuffer()
                    }
                    let content = try #require(reloaded).content
                    state.fileWatcherDidReloadActiveBuffer(buffer: buffer, content: content)
                })
            // The post-load pass lands before the next sample.
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH reload a changed file, main actor, 1M lines: \(Self.summary(samples))")
    }
}
