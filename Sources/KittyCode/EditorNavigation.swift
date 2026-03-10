import KittyCodecs
import KittyText

@MainActor
func jumpWordForward(state: EditorState) {
    TextNavigation.moveWordForward(cursor: &state.textCursor, in: state.textBuffer)
}

@MainActor
func jumpWordBackward(state: EditorState) {
    TextNavigation.moveWordBackward(cursor: &state.textCursor, in: state.textBuffer)
}

@MainActor
func ensureEditorVisible(_ state: EditorState, contentRows: Int = 20, availWidth: Int = 80) {
    TextNavigation.ensureVisible(
        cursor: &state.textCursor,
        visibleRows: contentRows,
        visibleCols: availWidth,
        wrapLines: state.config.wrapLines
    )
}
