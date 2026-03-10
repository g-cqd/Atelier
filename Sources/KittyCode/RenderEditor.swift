import KittyCodecs
import KittyRenderer

@MainActor
func renderEditorPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    editorStart: Int,
    editorWidth: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    var terminalCursorPos: (row: Int, col: Int)?

    if state.fileContent.isEmpty {
        renderEmptyEditor(
            pipeline: pipeline,
            editorStart: editorStart,
            editorWidth: editorWidth,
            contentRows: contentRows,
            colorScheme: colorScheme
        )
        return nil
    }

    if state.config.wrapLines {
        terminalCursorPos = renderWrappedEditor(
            pipeline: pipeline,
            state: state,
            editorStart: editorStart,
            editorWidth: editorWidth,
            contentRows: contentRows,
            lineNumWidth: lineNumWidth,
            colorScheme: colorScheme
        )
    } else {
        terminalCursorPos = renderScrollableEditor(
            pipeline: pipeline,
            state: state,
            editorStart: editorStart,
            editorWidth: editorWidth,
            contentRows: contentRows,
            lineNumWidth: lineNumWidth,
            colorScheme: colorScheme
        )
    }

    return terminalCursorPos
}
