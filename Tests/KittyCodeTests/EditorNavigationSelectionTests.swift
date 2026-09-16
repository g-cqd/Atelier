import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import KittyText
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct EditorNavigationSelectionTests {

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
        state.bufferManager.open(
            filePath: "/test.txt", fileName: "test.txt",
            content: "hello world\nsecond line\nthird line", language: nil)
        state.restoreStateFromActiveBuffer()
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    private func keyEvent(
        _ keyCode: UInt32, modifiers: KeyModifiers = [], eventType: KeyEventType = .press
    ) -> InputEvent {
        .key(KeyEvent(keyCode: keyCode, modifiers: modifiers, eventType: eventType))
    }

    // MARK: - Shift+Arrow creates selection

    @Test
    func shiftRightCreatesSelection() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0

        _ = handleEvent(
            event: keyEvent(Key.right.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection != nil)
        #expect(sut.state.selection?.anchor == TextPosition(row: 0, col: 0))
        #expect(sut.state.selection?.head == TextPosition(row: 0, col: 1))
    }

    @Test
    func shiftDownCreatesSelection() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 3

        _ = handleEvent(
            event: keyEvent(Key.down.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection != nil)
        #expect(sut.state.selection?.anchor == TextPosition(row: 0, col: 3))
        #expect(sut.state.selection?.head == TextPosition(row: 1, col: 3))
    }

    @Test
    func shiftHomeCreatesSelection() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5

        _ = handleEvent(
            event: keyEvent(Key.home.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection != nil)
        #expect(sut.state.selection?.anchor == TextPosition(row: 0, col: 5))
        #expect(sut.state.selection?.head == TextPosition(row: 0, col: 0))
    }

    @Test
    func shiftEndCreatesSelection() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0

        _ = handleEvent(
            event: keyEvent(Key.end.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection != nil)
        #expect(sut.state.selection?.anchor == TextPosition(row: 0, col: 0))
        #expect(sut.state.selection?.head == TextPosition(row: 0, col: 11))
    }

    // MARK: - Multiple shift+arrows extend selection

    @Test
    func multipleShiftRightExtendsSelection() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 0

        _ = handleEvent(
            event: keyEvent(Key.right.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )
        _ = handleEvent(
            event: keyEvent(Key.right.rawValue, modifiers: .shift),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection?.anchor == TextPosition(row: 0, col: 0))
        #expect(sut.state.selection?.head == TextPosition(row: 0, col: 2))
    }

    // MARK: - Plain arrow collapses selection

    @Test
    func plainRightCollapsesSelectionToEnd() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 2
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 0, col: 5)
        )

        _ = handleEvent(
            event: keyEvent(Key.right.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        #expect(sut.state.cursorCol == 5)
    }

    @Test
    func plainLeftCollapsesSelectionToStart() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 0, col: 5)
        )

        _ = handleEvent(
            event: keyEvent(Key.left.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        #expect(sut.state.cursorCol == 2)
    }

    @Test
    func plainUpCollapsesSelectionToStart() {
        let sut = makeSUT()
        sut.state.cursorRow = 1
        sut.state.cursorCol = 3
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 5),
            head: TextPosition(row: 1, col: 3)
        )

        _ = handleEvent(
            event: keyEvent(Key.up.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 5)
    }

    @Test
    func plainDownCollapsesSelectionToEnd() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 5),
            head: TextPosition(row: 1, col: 3)
        )

        _ = handleEvent(
            event: keyEvent(Key.down.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 3)
    }

    // MARK: - Backspace with selection deletes selection

    @Test
    func backspaceWithSelectionDeletesSelectedText() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 0, col: 5)
        )

        _ = handleEvent(
            event: keyEvent(Key.backspace.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        // "hello world" with chars 2-5 deleted → "he world"
        #expect(sut.state.fileLine(at: 0) == "he world")
    }

    // MARK: - Enter with selection replaces selection

    @Test
    func enterWithSelectionReplacesWithNewline() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 5
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 0, col: 5)
        )
        let lineCountBefore = sut.state.fileLineCount

        _ = handleEvent(
            event: keyEvent(Key.enter.rawValue),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selection == nil)
        // Selection deleted, then newline inserted: net +1 line
        #expect(sut.state.fileLineCount == lineCountBefore + 1)
    }
}
