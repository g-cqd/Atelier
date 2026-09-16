import KittyCodecs
import KittyRenderer
import KittyTerminal
import KittyText
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct CommandDispatcherTests {
    private func makeSUT(columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["line one", "line two"]
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    @Test
    func toggleSidebarTogglesSidebarCollapsed() {
        let sut = makeSUT()
        #expect(!sut.state.sidebarCollapsed)

        let result = dispatchCommand(.toggleSidebar, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.sidebarCollapsed)

        _ = dispatchCommand(.toggleSidebar, state: sut.state, pipeline: sut.pipeline)
        #expect(!sut.state.sidebarCollapsed)
    }

    @Test
    func nextTabAndPreviousTabCycleActiveIndex() {
        let sut = makeSUT()
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "a", language: nil)
        sut.state.bufferManager.open(
            filePath: "/b.txt", fileName: "b.txt", content: "b", language: nil)

        #expect(sut.state.bufferManager.activeIndex == 1)

        _ = dispatchCommand(.previousTab, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.bufferManager.activeIndex == 0)

        _ = dispatchCommand(.nextTab, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.bufferManager.activeIndex == 1)
    }

    @Test
    func quitAppReturnsFalse() {
        let sut = makeSUT()
        sut.state.mode = .tree

        let result = dispatchCommand(.handleCtrlX, state: sut.state, pipeline: sut.pipeline)

        #expect(!result)
    }

    @Test
    func handleCtrlXInEditorModeExitsToTree() {
        let sut = makeSUT()
        sut.state.mode = .editor

        let result = dispatchCommand(.handleCtrlX, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.mode == .tree)
    }

    @Test
    func saveFileDispatchesSave() {
        let sut = makeSUT()
        // saveFile on a fresh state with no file path just sets a status message
        let result = dispatchCommand(.saveFile, state: sut.state, pipeline: sut.pipeline)
        #expect(result)
    }

    @Test
    func undoRedoDispatch() {
        let sut = makeSUT()
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.textCursor.col = 5

        insertText("!", into: sut.state)
        #expect(sut.state.fileContent == ["hello!"])

        let undoResult = dispatchCommand(.undo, state: sut.state, pipeline: sut.pipeline)
        #expect(undoResult)
        #expect(sut.state.fileContent == ["hello"])

        let redoResult = dispatchCommand(.redo, state: sut.state, pipeline: sut.pipeline)
        #expect(redoResult)
        #expect(sut.state.fileContent == ["hello!"])
    }
}
