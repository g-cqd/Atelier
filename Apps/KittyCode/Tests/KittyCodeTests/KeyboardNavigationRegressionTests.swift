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
struct KeyboardNavigationRegressionTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        EditorTestHarness.make(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `handleEvent moves cursor for repeated arrow keys`() {
        let sut = makeSUT(fileContent: ["one", "two", "three"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.down.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func `handleEvent keeps option arrow repeat semantics`() {
        let sut = makeSUT(fileContent: ["alpha beta gamma"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue, modifiers: .alt, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorCol == 6)
    }

    @Test
    func `left arrow wraps to previous line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 1
        state.cursorCol = 0

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.left.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 2)
    }

    @Test
    func `right arrow wraps to next line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 0
        state.cursorCol = 2

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 1)
        #expect(state.cursorCol == 0)
    }

    @Test
    func `modifier-only key presses do not scroll the editor to an offscreen cursor`() {
        let sut = makeSUT(fileContent: (0 ..< 80).map(String.init), rows: 12)
        sut.state.cursorRow = 40
        sut.state.scrollOffset = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: 0, modifiers: .super, eventType: .press)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 40)
        #expect(sut.state.scrollOffset == 0)
    }

    @Test
    func `modifier-only key presses preserve editor selection and text`() {
        let sut = makeSUT(fileContent: ["hello world"])
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )
        sut.state.selection = selection

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: 0, modifiers: .super, eventType: .press)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["hello world"])
        #expect(sut.state.selection == selection)
    }

    @Test
    func `handleEvent keeps page navigation working for repeated fn style keys`() {
        let sut = makeSUT(fileContent: (0 ..< 100).map(String.init), rows: 12)

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.pageDown.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 11)
    }

    @Test
    func `handleEvent down arrow keeps wrapped cursor target visible`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        config.editor.wrapLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.sidebarCollapsed = true
        state.fileContent = [
            "AAAABBBBCCCCDDDDEEEEFFFFGGGG",
            "target"
        ]

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 8, rows: 6)),
            columns: 8,
            rows: 6
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.down.rawValue)),
            state: state,
            pipeline: pipeline
        )

        renderFrame(pipeline: pipeline, state: state)
        let renderedRows = (0 ..< 5)
            .map { row in
                String((0 ..< 8).map { pipeline.buffer[row, $0].character })
            }

        #expect(handled)
        #expect(state.cursorRow == 1)
        #expect(
            renderedRows.contains(where: { $0.contains("targ") }),
            "Expected wrapped viewport to reveal the focused line, got rows: \(renderedRows)"
        )
    }

    @Test
    func `handleEvent ignores repeated escape after leaving the editor`() {
        let sut = makeSUT(fileContent: ["one"])

        let firstHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape)),
            state: sut.state,
            pipeline: sut.pipeline
        )
        let repeatedHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(firstHandled)
        #expect(repeatedHandled)
        #expect(sut.state.mode == .tree)
    }

    @Test
    func `plain g inserts text in non-vim editor mode`() {
        let sut = makeSUT(fileContent: ["hello"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.g)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["ghello"])
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 1)
    }

    @Test
    func `shift g remains a vim normal navigation command only`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindingMode = .vim

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.vimMode = .normal
        state.fileContent = ["one", "two", "three"]
        state.cursorRow = 0
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.g, modifiers: .shift, associatedText: "G")),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 2)
        #expect(state.fileContent == ["one", "two", "three"])
    }
}
