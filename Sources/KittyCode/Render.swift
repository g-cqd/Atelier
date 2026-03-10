import KittyCodecs
import KittyRenderer

@MainActor
func render(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    let colorScheme = state.colorScheme
    guard cols > 0 && rows > 2 else { return }

    let treeWidth = min(state.treePanelWidth, cols / 2)
    let editorStart = treeWidth + 1
    let editorWidth = cols - editorStart
    let contentRows = rows - 2

    let title = " KittyCode — \(state.rootPath) "
    let titlePadding = String(repeating: " ", count: max(0, cols - title.count))
    pipeline.buffer.write(String((title + titlePadding).prefix(cols)), row: 0, col: 0, style: colorScheme.titleBar)

    renderTreePanel(
        pipeline: pipeline,
        state: state,
        treeWidth: treeWidth,
        contentRows: contentRows,
        colorScheme: colorScheme
    )

    let terminalCursorPos = renderEditorPanel(
        pipeline: pipeline,
        state: state,
        editorStart: editorStart,
        editorWidth: editorWidth,
        contentRows: contentRows,
        colorScheme: colorScheme
    )

    let mode = state.mode == .tree ? "TREE" : "EDIT"
    let position = state.isFileEmpty ? "" : "Ln \(state.cursorRow + 1)/\(state.fileLineCount)"
    let statusLeft = " [\(mode)] \(state.statusMessage)"
    let statusRight = "\(position)  \(cols)x\(rows) "
    let statusLine = statusLeft + String(repeating: " ", count: max(0, cols - statusLeft.count - statusRight.count)) + statusRight
    pipeline.buffer.write(String(statusLine.prefix(cols)), row: rows - 1, col: 0, style: colorScheme.statusBar)

    if let pos = terminalCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else {
        pipeline.cursorRow = nil
        pipeline.cursorCol = nil
    }
}
