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

    for row in 0..<contentRows {
        let treeIndex = state.treeScrollOffset + row
        if treeIndex >= 0 && treeIndex < state.flatTree.count {
            let (depth, entry) = state.flatTree[treeIndex]
            let indent = String(repeating: " ", count: depth * 2)
            let label = indent + entry.icon + " " + entry.name
            let padded = label + String(repeating: " ", count: max(0, treeWidth - label.count))
            let style: Style
            if treeIndex == state.selectedTreeIndex {
                style = colorScheme.treeSelected
            } else if entry.isDirectory {
                style = colorScheme.treeDir
            } else {
                style = colorScheme.treeBg
            }
            pipeline.buffer.write(String(padded.prefix(treeWidth)), row: row + 1, col: 0, style: style)
        } else {
            pipeline.buffer.fill(row: row + 1, col: 0, width: treeWidth, height: 1, cell: Cell(character: " ", style: colorScheme.treeBg))
        }

        pipeline.buffer.write("│", row: row + 1, col: treeWidth, style: colorScheme.separator)
    }

    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    var terminalCursorPos: (row: Int, col: Int)?

    if state.fileContent.isEmpty {
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
                    row: row + 1,
                    col: editorStart,
                    style: Style(fg: .rgb(r: 100, g: 100, b: 100), bg: colorScheme.bg.bg)
                )
            } else {
                pipeline.buffer.fill(row: row + 1, col: editorStart, width: editorWidth, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
            }
        }
    } else if state.config.wrapLines {
        let availWidth = editorWidth - lineNumWidth
        var screenRow = 0
        var lineIndex = state.scrollOffset

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
    } else {
        let availWidth = editorWidth - lineNumWidth
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
    }

    let mode = state.mode == .tree ? "TREE" : "EDIT"
    let position = state.fileContent.isEmpty ? "" : "Ln \(state.cursorRow + 1)/\(state.fileContent.count)"
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