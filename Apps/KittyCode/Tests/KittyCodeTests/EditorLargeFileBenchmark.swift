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
        let state = EditorState(
            rootPath: ".", config: KittyConfig(), taskProvider: taskProvider, searchPool: EditorTestPool.shared)
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
            let state = EditorState(
                rootPath: ".", config: KittyConfig(), taskProvider: tasks, searchPool: EditorTestPool.shared)
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
        let state = EditorState(
            rootPath: ".", config: KittyConfig(), taskProvider: tasks, searchPool: EditorTestPool.shared)
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

    /// The main actor's share of closing one of two million-line tabs: the restore brings back the other, which a
    /// switch evicted, and highlights it again.
    @Test func `closing a million-line tab while another stays open`() async throws {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = try await makeOpenedState(tasks: tasks)
            // A second tab over the same text, switched to as a user does, which evicts the first.
            state.bufferManager.open(
                filePath: "/bench/second.swift", fileName: "second.swift", content: Self.text, language: "swift")
            state.bufferManager.switchTo(index: 0)
            let spawned = tasks.spawnedTaskCount
            state.switchToTab(1)
            try await awaitFullPass(tasks, after: spawned)
            state.saveStateToActiveBuffer()
            samples.append(clock.measure { state.closeCurrentTab() })
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH close one of two tabs, main actor, 1M lines: \(Self.summary(samples))")
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
                    let (file, replaced) = try #require(consume reloaded)
                    state.fileWatcherDidReloadActiveBuffer(
                        buffer: buffer, content: file.content, replaced: consume replaced)
                })
            // The post-load pass lands before the next sample.
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH reload a changed file, main actor, 1M lines: \(Self.summary(samples))")
    }

    /// A short Swift file opened through the open path once its read has finished, as a click in the tree does: the
    /// open saves the active buffer's state first, then installs the file.
    private func openSmallFile(in state: EditorState, tasks: TaskProviderSpy) async throws {
        let small = try WorkspaceFileLoading.decode(Data("let small = 1\nprint(small)\n".utf8))
        let spawned = tasks.spawnedTaskCount
        state.saveStateToActiveBuffer()
        state.finishOpeningFile(
            requestID: state.nextOpenRequestID(), path: "/bench/small.swift", name: "small.swift",
            loadedFile: small, language: "swift", modificationDate: nil)
        try await awaitFullPass(tasks, after: spawned)
    }

    /// The main actor's share of switching from the million-line tab to a short one: the switch evicts the outgoing
    /// buffer's caches, and the restore lets go of the workspace's copy of its highlights.
    @Test func `switching away from a million-line tab`() async throws {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = try await makeOpenedState(tasks: tasks)
            try await openSmallFile(in: state, tasks: tasks)
            // Back to the large tab, whose highlights and width the open left in its buffer.
            state.switchToTab(0)
            try await tasks.waitForAllTasks()
            samples.append(clock.measure { state.switchToTab(1) })
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH switch away from a large tab, main actor, 1M lines: \(Self.summary(samples))")
    }

    /// The main actor's share of opening a short file in preview mode while the million-line file is the preview:
    /// the new preview replaces the old one, whose buffer and highlights the state lets go of.
    @Test func `replacing a million-line preview`() async throws {
        let loadedFile = try WorkspaceFileLoading.decode(Data(Self.text.utf8))
        let small = try WorkspaceFileLoading.decode(Data("let small = 1\nprint(small)\n".utf8))
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = EditorState(
                rootPath: ".", config: KittyConfig(), taskProvider: tasks, searchPool: EditorTestPool.shared)
            state.config.tabRibbon.persistence = .preview
            state.lastRenderRows = 60
            state.finishOpeningFile(
                requestID: state.nextOpenRequestID(), path: "/bench/large.swift", name: "large.swift",
                loadedFile: loadedFile, language: "swift", modificationDate: nil)
            try await tasks.waitForAllTasks()
            // What the open does before its read.
            state.saveStateToActiveBuffer()
            let requestID = state.nextOpenRequestID()
            samples.append(
                clock.measure {
                    state.finishOpeningFile(
                        requestID: requestID, path: "/bench/small.swift", name: "small.swift", loadedFile: small,
                        language: "swift", modificationDate: nil)
                })
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH replace a large preview, main actor, 1M lines: \(Self.summary(samples))")
    }

    /// The main actor's share of reloading a changed million-line file in an inactive tab once its read has finished:
    /// the tab went inactive by an open, which keeps its highlights, and the reload replaces its text.
    @Test func `reloading a changed million-line file in an inactive tab`() async throws {
        let changed = try WorkspaceFileLoading.decode(Data((Self.text + "\n// changed on disk").utf8))
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< 11 {
            let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
            let state = try await makeOpenedState(tasks: tasks)
            let buffer = try #require(state.bufferManager.activeBuffer)
            try await openSmallFile(in: state, tasks: tasks)
            samples.append(
                try await clock.measure {
                    let reloaded = try await buffer.reloadFromDisk(offloadFileRead: { _ in changed }) {}
                    let (file, replaced) = try #require(consume reloaded)
                    state.fileWatcherDidReloadInactiveBuffer(
                        buffer: buffer, content: file.content, replaced: consume replaced)
                })
            // The post-load pass lands before the next sample.
            try await tasks.waitForAllTasks()
            state.shutdown()
        }
        print("BENCH reload a changed file in an inactive tab, main actor, 1M lines: \(Self.summary(samples))")
    }
}
