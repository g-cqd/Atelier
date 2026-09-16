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
struct VimCommandLineTests {

    private func makeSUT(
        columns: Int = 80,
        rows: Int = 24
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindingMode = .vim
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.vimMode = .normal
        state.bufferManager.open(
            filePath: "/test.txt", fileName: "test.txt",
            content: "hello world\nsecond line", language: nil)
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

    private func enterCommandLine(_ sut: (state: EditorState, pipeline: RenderPipeline)) {
        _ = handleEvent(
            event: keyEvent(AsciiKey.colon), state: sut.state, pipeline: sut.pipeline)
    }

    // MARK: - Entering command-line mode

    @Test
    func colonEntersCommandLineMode() {
        let sut = makeSUT()
        enterCommandLine(sut)
        #expect(sut.state.vimCommandLine != nil)
        #expect(sut.state.statusMessage == ":")
    }

    @Test
    func colonDoesNotEnterCommandLineInInsertMode() {
        let sut = makeSUT()
        sut.state.vimMode = .insert
        _ = handleEvent(
            event: keyEvent(AsciiKey.colon), state: sut.state, pipeline: sut.pipeline)
        #expect(sut.state.vimCommandLine == nil)
    }

    // MARK: - Typing characters

    @Test
    func typingAppendsToBuffer() {
        let sut = makeSUT()
        enterCommandLine(sut)

        _ = sut.state.handleVimCommandLineKey(
            KeyEvent(keyCode: AsciiKey.w))

        #expect(sut.state.vimCommandLine?.buffer == "w")
        #expect(sut.state.statusMessage == ":w")
    }

    @Test
    func typingMultipleCharacters() {
        let sut = makeSUT()
        enterCommandLine(sut)

        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.w))
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.q))

        #expect(sut.state.vimCommandLine?.buffer == "wq")
        #expect(sut.state.statusMessage == ":wq")
    }

    // MARK: - Backspace

    @Test
    func backspaceRemovesLastCharacter() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.w))
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.q))

        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.backspace.rawValue))

        #expect(sut.state.vimCommandLine?.buffer == "w")
        #expect(sut.state.statusMessage == ":w")
    }

    @Test
    func backspaceOnEmptyBufferCancels() {
        let sut = makeSUT()
        enterCommandLine(sut)

        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.backspace.rawValue))

        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.statusMessage.hasPrefix("-- NORMAL --"))
    }

    // MARK: - Escape

    @Test
    func escapeCancelsCommandLine() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.w))

        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.escape))

        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.statusMessage.hasPrefix("-- NORMAL --"))
    }

    // MARK: - :w (save)

    @Test
    func colonWSaves() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.w))

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(result)
        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.mode == .editor)
    }

    // MARK: - :q (quit)

    @Test
    func colonQSwitchesToTreeMode() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.q))

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(result)
        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.mode == .tree)
    }

    // MARK: - :wq (save and quit)

    @Test
    func colonWQSavesAndSwitchesToTree() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.w))
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.q))

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(result)
        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.mode == .tree)
    }

    // MARK: - :q! (force quit)

    @Test
    func colonQBangReturnsFalse() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.q))
        // Type '!'
        _ = sut.state.handleVimCommandLineKey(
            KeyEvent(keyCode: 0x21))  // '!' = 0x21

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(!result)
        #expect(sut.state.vimCommandLine == nil)
    }

    // MARK: - :x (alias for :wq)

    @Test
    func colonXSavesAndSwitchesToTree() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.x))

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(result)
        #expect(sut.state.mode == .tree)
    }

    // MARK: - Unknown command

    @Test
    func unknownCommandShowsErrorMessage() {
        let sut = makeSUT()
        enterCommandLine(sut)
        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.z))

        let result = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: Key.enter.rawValue))

        #expect(result)
        #expect(sut.state.vimCommandLine == nil)
        #expect(sut.state.statusMessage == "Unknown command: :z")
    }

    // MARK: - KeyContext routing

    @Test
    func vimCommandLineContextRouting() {
        let sut = makeSUT()
        #expect(KeyContext.from(state: sut.state) == .editorVimNormal)

        enterCommandLine(sut)
        #expect(KeyContext.from(state: sut.state) == .editorVimCommandLine)

        _ = sut.state.handleVimCommandLineKey(KeyEvent(keyCode: AsciiKey.escape))
        #expect(KeyContext.from(state: sut.state) == .editorVimNormal)
    }

    // MARK: - Integration: keys are intercepted during command-line mode

    @Test
    func arrowKeysDontMoveCursorDuringCommandLine() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        enterCommandLine(sut)

        _ = handleEvent(
            event: keyEvent(Key.down.rawValue), state: sut.state, pipeline: sut.pipeline)

        // Cursor should NOT have moved — down key is consumed by command-line handler
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.vimCommandLine != nil)
    }
}
