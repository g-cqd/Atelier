import KittyCodecs
import KittyRenderer
import KittyText

@MainActor
func handleEditorKey(_ key: KeyEvent, state: EditorState, contentRows: Int, pipeline: RenderPipeline) -> Bool {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorWidth = pipeline.columns - treeWidth - 1
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    let availWidth = editorWidth - lineNumWidth

    if state.config.keybindingMode == .vim && state.vimMode == .normal {
        switch key.keyCode {
        case AsciiKey.i:
            state.vimMode = .insert
            state.statusMessage = "-- INSERT -- [\(state.fileName)]"
        case AsciiKey.h:
            state.cursorCol = max(0, state.cursorCol - 1)
        case AsciiKey.j:
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
        case AsciiKey.k:
            state.cursorRow = max(0, state.cursorRow - 1)
        case AsciiKey.l:
            let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLength)
        case AsciiKey.colon:
            state.statusMessage = ":"
        case AsciiKey.w:
            if state.statusMessage == ":" {
                state.saveFile()
            }
        default:
            break
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        return true
    }

    switch key.keyCode {
    case Key.down.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
        } else {
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
        }
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.up.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = max(state.cursorRow - contentRows, 0)
        } else {
            state.cursorRow = max(state.cursorRow - 1, 0)
        }
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.left.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordBackward(state: state)
        } else {
            state.cursorCol = max(state.cursorCol - 1, 0)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.right.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordForward(state: state)
        } else {
            let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLength)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case AsciiKey.b:
        if key.modifiers == .alt {
            jumpWordBackward(state: state)
        }
    case AsciiKey.f:
        if key.modifiers == .alt {
            jumpWordForward(state: state)
        }
    case Key.home.rawValue:
        state.cursorCol = 0
    case Key.end.rawValue:
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = rowLength
    case Key.pageUp.rawValue:
        state.cursorRow = max(state.cursorRow - contentRows, 0)
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.pageDown.rawValue:
        state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.enter.rawValue, Key.enterAlt.rawValue:
        let lineBeforeEdit = state.textCursor.row
        TextOperations.insertNewline(into: &state.textBuffer, at: &state.textCursor)
        // Newline splits a line — invalidate from the split point onward
        for key in state.highlightCache.keys where key >= lineBeforeEdit {
            state.highlightCache.removeValue(forKey: key)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        let lineBeforeEdit = state.textCursor.row
        TextOperations.deleteBackward(in: &state.textBuffer, at: &state.textCursor)
        // Backspace may merge lines — invalidate from current line onward
        let invalidateFrom = min(lineBeforeEdit, state.textCursor.row)
        for key in state.highlightCache.keys where key >= invalidateFrom {
            state.highlightCache.removeValue(forKey: key)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case AsciiKey.g:
        if key.modifiers == .shift {
            state.cursorRow = max(0, state.fileContent.count - 1)
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        } else {
            state.cursorRow = 0
            state.cursorCol = 0
            state.scrollOffset = 0
        }
    default:
        if !key.associatedText.isEmpty {
            insertText(key.associatedText, into: state)
        } else if key.keyCode < 256, let scalar = UnicodeScalar(key.keyCode) {
            let char = Character(scalar)
            if char.isPrintable {
                insertText(String(char), into: state)
            }
        }
    }

    ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    return true
}
