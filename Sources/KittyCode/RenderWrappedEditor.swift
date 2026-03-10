import KittyCodecs
import KittyRenderer

@MainActor
func renderWrappedEditor(
    pipeline: RenderPipeline,
    state: EditorState,
    editorStart: Int,
    editorWidth: Int,
    contentRows: Int,
    lineNumWidth: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    let availWidth = editorWidth - lineNumWidth
    var screenRow = 0
    var lineIndex = state.scrollOffset
    var terminalCursorPos: (row: Int, col: Int)?

    while screenRow < contentRows && lineIndex < state.fileContent.count {
        let isCurrentLine = lineIndex == state.cursorRow
        let spans = highlightSwift(state.fileContent[lineIndex], colorScheme: colorScheme)
        let flat = flattenSpans(spans)
        let totalChars = max(flat.count, 1)
        let wrappedRowCount = max(1, (totalChars + availWidth - 1) / availWidth)

        for wrapRow in 0..<wrappedRowCount {
            guard screenRow < contentRows else { break }
            let row = screenRow + 1

            if wrapRow == 0 {
                let num = String(lineIndex + 1)
                let numPad = String(repeating: " ", count: max(0, lineNumWidth - num.count - 1))
                pipeline.buffer.write(numPad + num + " ", row: row, col: editorStart, style: colorScheme.lineNumber)
            } else {
                pipeline.buffer.fill(row: row, col: editorStart, width: lineNumWidth, height: 1, cell: Cell(character: " ", style: colorScheme.lineNumber))
            }

            let segStart = wrapRow * availWidth
            let segEnd = min(segStart + availWidth, flat.count)
            var col = editorStart + lineNumWidth
            for index in segStart..<segEnd {
                var style = flat[index].1
                if isCurrentLine {
                    style.bg = colorScheme.editorCursorLine.bg
                }
                pipeline.buffer[row, col] = Cell(character: flat[index].0, style: style)
                col += 1
            }

            let padStyle = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
            while col < editorStart + editorWidth {
                pipeline.buffer[row, col] = Cell(character: " ", style: padStyle)
                col += 1
            }

            if isCurrentLine && state.mode == .editor {
                let cursorWrapRow = state.cursorCol / availWidth
                let cursorWrapCol = state.cursorCol % availWidth
                if wrapRow == cursorWrapRow {
                    terminalCursorPos = (row: row, col: editorStart + lineNumWidth + cursorWrapCol)
                }
            }

            screenRow += 1
        }

        lineIndex += 1
    }

    while screenRow < contentRows {
        let row = screenRow + 1
        pipeline.buffer.write("~", row: row, col: editorStart, style: colorScheme.lineNumber)
        pipeline.buffer.fill(row: row, col: editorStart + 1, width: editorWidth - 1, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
        screenRow += 1
    }

    return terminalCursorPos
}