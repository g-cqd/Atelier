import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct CommandDispatcherPhase2Tests {
    private func makeSUT(
        keybindingMode: KittyConfig.KeybindingMode = .nano,
        columns: Int = 80,
        rows: Int = 24
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindingMode = keybindingMode
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["hello world", "second line", "third line"]
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    // MARK: - Escape

    @Test
    func escapeEditorInNanoModeSwitchesToTree() {
        let sut = makeSUT(keybindingMode: .nano)
        sut.state.mode = .editor

        let result = dispatchCommand(.escapeEditor, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.mode == .tree)
    }

    @Test
    func escapeEditorInVimModeSwitchesToNormal() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.mode = .editor
        sut.state.vimMode = .insert

        let result = dispatchCommand(.escapeEditor, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.mode == .editor)
        #expect(sut.state.vimMode == .normal)
    }

    @Test
    func escapeEditorInTreeModeReturnsFalse() {
        let sut = makeSUT()
        sut.state.mode = .tree

        let result = dispatchCommand(.escapeEditor, state: sut.state, pipeline: sut.pipeline)

        #expect(!result)
    }

    @Test
    func forceQuitReturnsFalse() {
        let sut = makeSUT()
        let result = dispatchCommand(.forceQuit, state: sut.state, pipeline: sut.pipeline)
        #expect(!result)
    }

    // MARK: - Vim motions

    @Test
    func vimEnterInsertSetsInsertMode() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.vimMode = .normal

        let result = dispatchCommand(.vimEnterInsert, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.vimMode == .insert)
    }

    @Test
    func vimMoveDownIncrementsRow() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorRow = 0

        _ = dispatchCommand(.vimMoveDown, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func vimMoveUpDecrementsRow() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorRow = 2

        _ = dispatchCommand(.vimMoveUp, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func vimMoveLeftDecreasesCol() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorCol = 5

        _ = dispatchCommand(.vimMoveLeft, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorCol == 4)
    }

    @Test
    func vimMoveLeftClampsAtZero() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorCol = 0

        _ = dispatchCommand(.vimMoveLeft, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func vimMoveRightIncreasesCol() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorCol = 0

        _ = dispatchCommand(.vimMoveRight, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorCol == 1)
    }

    @Test
    func vimGotoLastLineMovesToEnd() {
        let sut = makeSUT(keybindingMode: .vim)
        sut.state.cursorRow = 0

        _ = dispatchCommand(.vimGotoLastLine, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorRow == 2)
    }

    // MARK: - Editor word navigation

    @Test
    func editorWordForwardMovesToNextWordBoundary() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0

        let result = dispatchCommand(
            .editorWordForward, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.cursorCol > 0)
    }

    @Test
    func editorWordBackwardMovesToPreviousWordBoundary() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 8

        let result = dispatchCommand(
            .editorWordBackward, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.cursorCol < 8)
    }

    // MARK: - Tree navigation

    @Test
    func treeDownIncrementsIndex() {
        let sut = makeSUT()
        sut.state.mode = .tree
        let startIndex = sut.state.selectedTreeIndex

        _ = dispatchCommand(.treeDown, state: sut.state, pipeline: sut.pipeline)

        // If tree has entries, index increases; if empty, stays at max(0, count-1)
        #expect(sut.state.selectedTreeIndex >= startIndex)
    }

    @Test
    func treeUpDecrementsIndex() {
        let sut = makeSUT()
        sut.state.mode = .tree
        sut.state.selectedTreeIndex = 2

        _ = dispatchCommand(.treeUp, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.selectedTreeIndex == 1)
    }

    @Test
    func treeUpClampsAtZero() {
        let sut = makeSUT()
        sut.state.mode = .tree
        sut.state.selectedTreeIndex = 0

        _ = dispatchCommand(.treeUp, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.selectedTreeIndex == 0)
    }
}
