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
struct ClipboardAndHistoryShortcutTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        EditorTestHarness.make(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `command copy uses the active selection by default`() {
        let sut = makeSUT(fileContent: ["hello world"])
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )
        var writes: [[UInt8]] = []
        sut.state.terminalWriter = { writes.append($0) }

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.c, modifiers: .super)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(!writes.isEmpty)
        #expect(sut.state.fileContent == ["hello world"])
        #expect(sut.state.selection != nil)
    }

    @Test
    func `command paste requests clipboard by default`() {
        let sut = makeSUT(fileContent: ["hello world"])
        var writes: [[UInt8]] = []
        sut.state.terminalWriter = { writes.append($0) }

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.v, modifiers: .super)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(writes == [KittySequences.requestClipboard])
    }

    @Test
    func `clipboard shortcut modifier can be configured back to control`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindings.clipboardModifier = .control

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        state.restoreStateFromActiveBuffer()
        state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 6),
            head: TextPosition(row: 0, col: 11)
        )
        var writes: [[UInt8]] = []
        state.terminalWriter = { writes.append($0) }
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)),
            columns: 80,
            rows: 24
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.c, modifiers: .ctrl)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(!writes.isEmpty)
        #expect(state.fileContent == ["hello world"])
    }

    @Test
    func `history shortcut modifier can be configured back to control`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.keybindings.historyModifier = .control

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)),
            columns: 80,
            rows: 24
        )

        insertText("!", into: state)

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.z, modifiers: .ctrl)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.fileContent == ["hello"])
    }
}
