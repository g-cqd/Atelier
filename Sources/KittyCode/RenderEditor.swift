import KittyCodecs
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func renderEditorPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    editorStart: Int,
    editorWidth: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    if state.isFileEmpty {
        renderEmptyEditor(
            pipeline: pipeline,
            editorStart: editorStart,
            editorWidth: editorWidth,
            contentRows: contentRows,
            colorScheme: colorScheme
        )
        return nil
    }

    let editor = TextEditor(
        lines: state.fileContent,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        wrapLines: state.config.wrapLines,
        editorStyle: colorScheme.editorText,
        lineNumberStyle: colorScheme.lineNumber,
        currentLineStyle: colorScheme.editorCursorLine,
        modeShowsCursor: state.mode == .editor
    )

    let rect = Rect(x: editorStart, y: 1, width: editorWidth, height: contentRows)
    editor.render(to: &pipeline.buffer, in: rect)
    guard let cursor = TextEditorLayout.cursorPosition(for: editor, in: rect) else {
        return nil
    }
    return (row: cursor.row, col: cursor.col)
}
