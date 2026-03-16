import KittyCodecs
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func handleEditorKey(
    _ key: KeyEvent, state: EditorState, contentRows: Int, pipeline: RenderPipeline
) -> Bool {
    // In vim normal mode, unresolved keys should not insert text
    if state.config.keybindingMode == .vim && state.vimMode == .normal {
        return true
    }

    // Text insertion fallback (printable characters not handled by KeymapResolver)
    if let insertedText = textInsertion(for: key, allowTab: true) {
        if state.hasActiveSelection, let selection = state.selection {
            let previousSnapshot = state.activeBufferSnapshot()
            let mutation = TextOperations.deleteRange(
                in: &state.textBuffer, at: &state.textCursor, selection: selection)
            state.textDidChange(mutation, previousSnapshot: previousSnapshot)
            state.clearSelection()
        }
        insertText(insertedText, into: state)
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        let editorRect = Rect(
            x: layout.editorStart,
            y: layout.contentStartRow,
            width: layout.editorWidth,
            height: layout.contentRows
        )
        let availWidth = max(
            1, TextEditorLayout.contentWidth(for: makeEditorView(state: state), in: editorRect))
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    }
    return true
}
