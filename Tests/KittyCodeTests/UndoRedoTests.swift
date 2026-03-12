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

@testable import KittyCode

@Suite
@MainActor
struct UndoRedoTests {
    private func makePipeline(columns: Int = 80, rows: Int = 24) -> RenderPipeline {
        RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
    }

    @Test
    func `buffer undo redo is per active buffer`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        let pipeline = makePipeline()

        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "a", language: nil)
        state.restoreStateFromActiveBuffer()
        state.mode = .editor
        state.cursorCol = 1
        insertText("1", into: state)

        state.saveStateToActiveBuffer()
        state.bufferManager.open(filePath: "/b.txt", fileName: "b.txt", content: "b", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorCol = 1
        insertText("2", into: state)

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.z, modifiers: .super)),
            state: state,
            pipeline: pipeline
        )

        #expect(state.documentText == "b")

        state.switchToTab(0)
        #expect(state.documentText == "a1")
    }

    @Test
    func `buffer undo coalesces nearby edits by default`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor
        insertText("a", into: state)
        insertText("b", into: state)

        state.undoActiveBuffer()

        #expect(state.documentText.isEmpty)
    }

    @Test
    func `buffer undo coalescing disabled keeps each keystroke separately undoable`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.undoCoalescingEnabled = false

        let state = EditorState(rootPath: ".", config: config)
        state.beginNewFile()
        state.mode = .editor

        insertText("a", into: state)
        insertText("b", into: state)

        state.undoActiveBuffer()
        #expect(state.documentText == "a")

        state.undoActiveBuffer()
        #expect(state.documentText.isEmpty)
    }

    @Test
    func `buffer undo invalidates after external refresh divergence`() throws {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.beginNewFile()
        state.mode = .editor
        insertText("local", into: state)

        let buffer = try #require(state.bufferManager.activeBuffer)
        buffer.textBuffer = TextBuffer("external")
        buffer.textCursor = TextCursor(col: 8)
        buffer.didInvalidateHistoryOnLastRefresh = buffer.editHistory.reconcileWithRefresh(
            BufferEditSnapshot(
                textBuffer: buffer.textBuffer,
                textCursor: buffer.textCursor,
                lineEnding: buffer.lineEnding
            )
        )
        state.restoreStateFromActiveBuffer()

        state.undoActiveBuffer()

        #expect(buffer.didInvalidateHistoryOnLastRefresh)
        #expect(state.statusMessage == "Nothing to undo")
        #expect(state.documentText == "external")
    }
}
