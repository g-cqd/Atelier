import KittyCodecs
import KittyRenderer

@MainActor
func renderEmptyEditor(
    pipeline: RenderPipeline,
    editorStart: Int,
    editorWidth: Int,
    contentStartRow: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    let message = "Open a file from the tree (Enter)"
    let messageRow = contentRows / 2
    for row in 0..<contentRows {
        if row == messageRow {
            let leftPadding = max(0, (editorWidth - message.count) / 2)
            let line = String(repeating: " ", count: leftPadding)
                + message
                + String(repeating: " ", count: max(0, editorWidth - leftPadding - message.count))
            pipeline.buffer.write(
                String(line.prefix(editorWidth)),
                row: contentStartRow + row,
                col: editorStart,
                style: Style(fg: .rgb(r: 100, g: 100, b: 100))
            )
        } else {
            pipeline.buffer.fill(row: contentStartRow + row, col: editorStart, width: editorWidth, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
        }
    }
}