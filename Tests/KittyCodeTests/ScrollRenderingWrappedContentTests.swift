import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct ScrollRenderingWrappedContentTests {

    @Test
    func `scrolling through an overheight wrapped line keeps later wrapped content visible`() throws
    {
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

        for _ in 0..<4 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        #expect(state.scrollOffset == 0)
        #expect(state.wrapRowOffset == 4)

        renderFrame(pipeline: pipeline, state: state)

        let topRowText = String((0..<8).map { pipeline.buffer[0, $0].character })
        #expect(
            topRowText.contains("EEEE"),
            "Expected wrapped continuation to remain visible after scrolling, got: \(topRowText)")

        let lastContentRowText = String((0..<8).map { pipeline.buffer[4, $0].character })
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
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = ["AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH", "after", "tail", "done"]
        state.refreshHighlights()

        renderFrame(pipeline: pipeline, state: state)

        for _ in 0..<12 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        let deadline = Date().addingTimeInterval(1)
        while state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil,
            Date() < deadline
        {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(state.scrollOffset == 3)
        #expect(state.wrapRowOffset == 0)
        renderFrame(pipeline: pipeline, state: state)

        #expect(state.pendingAcceleratedScrollLines == 0)
        #expect(state.scrollAccelerationTask == nil)

        let contentRows = (0..<5).map { row in
            String((0..<8).map { pipeline.buffer[row, $0].character })
        }
        let hasDone = contentRows.contains { $0.contains("done") || $0.contains("done".prefix(4)) }
        #expect(
            hasDone,
            "Expected bottom content to remain renderable after accelerated scrolling, got: \(contentRows)"
        )
    }
}
