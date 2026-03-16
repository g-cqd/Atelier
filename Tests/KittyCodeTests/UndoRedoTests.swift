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
    func `undo restores selection state`() {
        var config = KittyConfig()
        config.editor.undoCoalescingEnabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.beginNewFile()
        state.mode = .editor

        // Type some text (first edit)
        insertText("hello world", into: state)

        // Create a selection on the buffer
        let sel = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )
        state.selection = sel

        // Second edit — snapshot captures the selection in `before`
        insertText("!", into: state)

        // Undo the "!" edit — should restore the `before` snapshot which had the selection
        state.undoActiveBuffer()
        #expect(state.selection == sel)
    }

    @Test
    func `performUndo dispatches to buffer in editor mode`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.undoCoalescingEnabled = false
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor
        insertText("a", into: state)

        state.performUndo()
        #expect(state.documentText.isEmpty)
    }

    @Test
    func `performUndo dispatches to tree in tree mode`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.undoCoalescingEnabled = false
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor
        insertText("a", into: state)

        // Switch to tree mode — performUndo should NOT touch the buffer
        state.mode = .tree
        state.performUndo()
        #expect(state.documentText == "a")
    }

    @Test
    func `performRedo dispatches to buffer in editor mode`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.undoCoalescingEnabled = false
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor
        insertText("a", into: state)

        state.undoActiveBuffer()
        #expect(state.documentText.isEmpty)

        state.performRedo()
        #expect(state.documentText == "a")
    }

    @Test
    func `editor context menu includes undo when available`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor
        insertText("x", into: state)

        state.showEditorContextMenu()
        let titles = state.contextMenu?.items.map(\.title) ?? []
        #expect(titles.contains("Undo"))
    }

    @Test
    func `editor context menu excludes undo when unavailable`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        state.beginNewFile()
        state.mode = .editor

        state.showEditorContextMenu()
        let titles = state.contextMenu?.items.map(\.title) ?? []
        #expect(!titles.contains("Undo"))
        #expect(!titles.contains("Redo"))
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
