import KittyCodecs
import KittyRenderer

@MainActor
func renderScrollableEditor(
    pipeline: RenderPipeline,
    state: EditorState,
    editorStart: Int,
    editorWidth: Int,
    contentRows: Int,
    lineNumWidth: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    let availWidth = editorWidth - lineNumWidth
    var terminalCursorPos: (row: Int, col: Int)?

    for row in 0..<contentRows {
        let lineIndex = state.scrollOffset + row
        let isCurrentLine = lineIndex == state.cursorRow

        if lineIndex >= 0 && lineIndex < state.fileContent.count {
            let num = String(lineIndex + 1)
            let numPad = String(repeating: " ", count: max(0, lineNumWidth - num.count - 1))
            pipeline.buffer.write(numPad + num + " ", row: row + 1, col: editorStart, style: colorScheme.lineNumber)

            let spans = highlightSwift(state.fileContent[lineIndex], colorScheme: colorScheme)
            renderStyledSpans(
                pipeline: pipeline,
                spans: spans,
                row: row + 1,
                col: editorStart + lineNumWidth,
                availWidth: availWidth,
                hScrollOffset: state.hScrollOffset,
                isCurrentLine: isCurrentLine,
                colorScheme: colorScheme
            )

            if isCurrentLine && state.mode == .editor {
                let relativeCol = state.cursorCol - state.hScrollOffset
                if relativeCol >= 0 && relativeCol < availWidth {
                    terminalCursorPos = (row: row + 1, col: editorStart + lineNumWidth + relativeCol)
                }
            }
        } else {
            pipeline.buffer.write("~", row: row + 1, col: editorStart, style: colorScheme.lineNumber)
            pipeline.buffer.fill(row: row + 1, col: editorStart + 1, width: editorWidth - 1, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
        }
    }

    return terminalCursorPos
}