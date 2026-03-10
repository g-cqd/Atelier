import KittyCodecs
import KittyRenderer
import KittyText

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
        let spans = state.cachedHighlightLine(lineIndex)

        // Count total display width by walking spans directly (no intermediate array)
        var totalWidth = 0
        for span in spans {
            for char in span.text {
                totalWidth += UnicodeWidth.displayWidth(of: char)
            }
        }
        totalWidth = max(totalWidth, 1)
        let wrappedRowCount = max(1, (totalWidth + availWidth - 1) / availWidth)

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

            // Walk spans directly for this wrap row's segment (width-aware)
            let segStartWidth = wrapRow * availWidth
            let segEndWidth = min(segStartWidth + availWidth, totalWidth)
            var col = editorStart + lineNumWidth
            var widthPos = 0
            for span in spans {
                if widthPos >= segEndWidth { break }
                for char in span.text {
                    let w = UnicodeWidth.displayWidth(of: char)
                    if widthPos + w > segEndWidth { break }
                    if widthPos >= segStartWidth {
                        var style = span.style
                        if isCurrentLine {
                            style.bg = colorScheme.editorCursorLine.bg
                        }
                        if w == 2 && col + 1 < editorStart + editorWidth {
                            pipeline.buffer[row, col] = Cell(character: char, style: style, width: 2)
                            pipeline.buffer[row, col + 1] = Cell(character: "\0", style: style, width: 0)
                            col += 2
                        } else if w == 1 {
                            pipeline.buffer[row, col] = Cell(character: char, style: style)
                            col += 1
                        }
                    }
                    widthPos += w
                }
            }

            let padStyle = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
            while col < editorStart + editorWidth {
                pipeline.buffer[row, col] = Cell(character: " ", style: padStyle)
                col += 1
            }

            if isCurrentLine && state.mode == .editor {
                let line = state.fileContent[lineIndex]
                let cursorDisplayCol = displayColumn(for: state.cursorCol, in: line)
                let cursorWrapRow = cursorDisplayCol / availWidth
                let cursorWrapCol = cursorDisplayCol % availWidth
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
