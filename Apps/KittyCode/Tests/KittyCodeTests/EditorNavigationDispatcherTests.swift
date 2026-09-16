import AtelierText
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct EditorNavigationDispatcherTests {
    private func makeSUT(
        columns: Int = 80,
        rows: Int = 24
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindingMode = .nano
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["hello world", "second line", "third line", "fourth line"]
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    // MARK: - editorMoveDown

    @Test
    func moveDownIncrementsRow() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        _ = dispatchCommand(.editorMoveDown, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func moveDownClampsAtLastLine() {
        let sut = makeSUT()
        sut.state.cursorRow = 3
        _ = dispatchCommand(.editorMoveDown, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow == 3)
    }

    @Test
    func moveDownClampsCursorCol() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 11  // "hello world".count
        _ = dispatchCommand(.editorMoveDown, state: sut.state, pipeline: sut.pipeline)
        // "second line".count == 11, col stays at 11
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 11)
    }

    // MARK: - editorMoveUp

    @Test
    func moveUpDecrementsRow() {
        let sut = makeSUT()
        sut.state.cursorRow = 2
        _ = dispatchCommand(.editorMoveUp, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func moveUpClampsAtZero() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        _ = dispatchCommand(.editorMoveUp, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow == 0)
    }

    // MARK: - editorMoveLeft / Right

    @Test
    func moveLeftDecrementsCursorCol() {
        let sut = makeSUT()
        sut.state.cursorCol = 5
        _ = dispatchCommand(.editorMoveLeft, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorCol == 4)
    }

    @Test
    func moveRightIncrementsCursorCol() {
        let sut = makeSUT()
        sut.state.cursorCol = 0
        _ = dispatchCommand(.editorMoveRight, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorCol == 1)
    }

    // MARK: - Page navigation

    @Test
    func moveDownPageJumpsByContentRows() {
        let sut = makeSUT(rows: 10)
        sut.state.fileContent = (0 ..< 50).map { "line \($0)" }
        sut.state.cursorRow = 0
        _ = dispatchCommand(.editorMoveDownPage, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow > 1)
    }

    @Test
    func moveUpPageJumpsBackward() {
        let sut = makeSUT(rows: 10)
        sut.state.fileContent = (0 ..< 50).map { "line \($0)" }
        sut.state.cursorRow = 20
        _ = dispatchCommand(.editorMoveUpPage, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorRow < 20)
    }

    // MARK: - Home / End

    @Test
    func homeSetsColToZero() {
        let sut = makeSUT()
        sut.state.cursorCol = 5
        _ = dispatchCommand(.editorHome, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func endSetsColToLineLength() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0
        _ = dispatchCommand(.editorEnd, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorCol == 11)  // "hello world".count
    }

    // MARK: - Insert newline

    @Test
    func insertNewlineAddsLine() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        let lineCountBefore = sut.state.fileLineCount
        _ = dispatchCommand(.editorInsertNewline, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.fileLineCount == lineCountBefore + 1)
    }

    // MARK: - Delete backward

    @Test
    func deleteBackwardRemovesCharacter() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        _ = dispatchCommand(.editorDeleteBackward, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.cursorCol == 4)
    }

    @Test
    func deleteBackwardAtStartOfFileDoesNothing() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0
        let lineCountBefore = sut.state.fileLineCount
        _ = dispatchCommand(.editorDeleteBackward, state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.fileLineCount == lineCountBefore)
        #expect(sut.state.cursorCol == 0)
    }

    // MARK: - All commands return true

    @Test
    func allNavigationCommandsReturnTrue() {
        let sut = makeSUT()
        sut.state.cursorRow = 1
        sut.state.cursorCol = 3
        let commands: [CommandID] = [
            .editorMoveDown, .editorMoveUp, .editorMoveLeft, .editorMoveRight,
            .editorHome, .editorEnd, .editorInsertNewline, .editorDeleteBackward
        ]
        for command in commands {
            let result = dispatchCommand(command, state: sut.state, pipeline: sut.pipeline)
            #expect(result, "Expected \(command) to return true")
        }
    }
}
