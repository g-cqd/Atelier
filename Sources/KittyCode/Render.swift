import KittyCodecs
import KittyRenderer
import KittyWidgets

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

    StatusBar(
        left: " KittyCode — \(state.rootPath) ",
        style: colorScheme.titleBar
    ).render(to: &pipeline.buffer, in: Rect(x: 0, y: 0, width: cols, height: 1))

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
    StatusBar(
        left: statusLeft,
        right: statusRight,
        style: colorScheme.statusBar
    ).render(to: &pipeline.buffer, in: Rect(x: 0, y: rows - 1, width: cols, height: 1))

    if let pos = terminalCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else {
        pipeline.cursorRow = nil
        pipeline.cursorCol = nil
    }
}
