@MainActor
func moveCursorLeft(state: EditorState) {
    if state.config.editor.arrowKeysWrapAcrossLines,
       state.cursorCol == 0,
       state.cursorRow > 0 {
        state.cursorRow -= 1
        state.cursorCol = state.fileLine(at: state.cursorRow).count
        return
    }

    state.cursorCol = max(state.cursorCol - 1, 0)
}

@MainActor
func moveCursorRight(state: EditorState) {
    let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
    if state.config.editor.arrowKeysWrapAcrossLines,
       state.cursorCol >= rowLength,
       state.cursorRow < max(0, state.fileLineCount - 1) {
        state.cursorRow += 1
        state.cursorCol = 0
        return
    }

    state.cursorCol = min(state.cursorCol + 1, rowLength)
}
