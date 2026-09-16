import AemiTesting
import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct ScrollRenderingWrappedContentTests {
    @Test
    func `scrolling through an overheight wrapped line keeps later wrapped content visible`() throws {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 8, rows: 6))
        let pipeline = RenderPipeline(connection: mock, columns: 8, rows: 6)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        config.editor.wrapLines = true
        config.editor.scrollLines = 1
        config.editor.scrollAccelerationEnabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = ["AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH", "after"]
        state.refreshHighlights()

        renderFrame(pipeline: pipeline, state: state)

        for _ in 0 ..< 4 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        #expect(state.scrollOffset == 0)
        #expect(state.wrapRowOffset == 4)

        renderFrame(pipeline: pipeline, state: state)

        let topRowText = String((0 ..< 8).map { pipeline.buffer[0, $0].character })
        #expect(
            topRowText.contains("EEEE"),
            "Expected wrapped continuation to remain visible after scrolling, got: \(topRowText)")

        let lastContentRowText = String((0 ..< 8).map { pipeline.buffer[4, $0].character })
        #expect(
            lastContentRowText.contains("afte"),
            "Expected following line to appear after wrapped continuation rows, got: \(lastContentRowText)"
        )
    }

    @Test
    func `accelerating into wrapped content edge does not crash or leave invalid state`()
        async throws
    {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 8, rows: 6))
        let pipeline = RenderPipeline(connection: mock, columns: 8, rows: 6)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        config.editor.wrapLines = true
        config.editor.scrollLines = 1
        config.editor.scrollAccelerationEnabled = true
        config.editor.scrollAccelerationWindowMilliseconds = 200
        config.editor.scrollAccelerationStepIntervalMilliseconds = 1
        config.editor.scrollAccelerationMaxExtraLines = 8
        let taskProvider = TaskProviderSpy()
        let clock = TestClock()
        let state = EditorState(rootPath: ".", config: config, taskProvider: taskProvider, clock: clock)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = ["AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH", "after", "tail", "done"]
        state.refreshHighlights()

        renderFrame(pipeline: pipeline, state: state)

        for _ in 0 ..< 12 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        // Drains the accelerated-scroll loop's repeated `clock.sleep` steps: a pump task advances
        // the virtual clock every time the loop registers a new sleeper, racing against the real
        // completion of the detached scroll task; the first to finish cancels the other.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await taskProvider.waitForAllTasks(timeout: .seconds(30))
            }
            group.addTask {
                while true {
                    try Task.checkCancellation()
                    try await clock.waitForSleepers(count: 1)
                    clock.advance(by: .milliseconds(1))
                }
            }
            try await group.next()
            group.cancelAll()
        }

        #expect(state.scrollOffset == 3)
        #expect(state.wrapRowOffset == 0)
        renderFrame(pipeline: pipeline, state: state)

        #expect(state.pendingAcceleratedScrollLines == 0)
        #expect(state.scrollAccelerationTask == nil)

        let contentRows = (0 ..< 5)
            .map { row in
                String((0 ..< 8).map { pipeline.buffer[row, $0].character })
            }
        let hasDone = contentRows.contains { $0.contains("done") || $0.contains("done".prefix(4)) }
        #expect(
            hasDone,
            "Expected bottom content to remain renderable after accelerated scrolling, got: \(contentRows)"
        )
    }
}
