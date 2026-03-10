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
        lineSpans: (0..<state.fileLineCount).map { state.highlightedLine(at: $0) },
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

    let lineNumWidth = max(3, String(state.fileLineCount).count + 1)
    let availWidth = max(1, editorWidth - lineNumWidth)
    guard state.mode == .editor else { return nil }

    if state.config.wrapLines {
        let line = state.fileLine(at: state.cursorRow)
        let cursorDisplayCol = displayColumn(for: state.cursorCol, in: line)
        let cursorWrapRow = cursorDisplayCol / availWidth
        let cursorWrapCol = cursorDisplayCol % availWidth

        var screenRow = 0
        var lineIndex = state.scrollOffset
        while lineIndex < state.fileLineCount {
            let spans = state.highlightedLine(at: lineIndex)
            let totalWidth = max(1, spans.reduce(into: 0) { partial, span in
                for char in span.text { partial += UnicodeWidth.displayWidth(of: char) }
            })
            let wrappedRowCount = max(1, (totalWidth + availWidth - 1) / availWidth)

            if lineIndex == state.cursorRow {
                let targetRow = screenRow + cursorWrapRow
                guard targetRow < contentRows else { return nil }
                return (row: targetRow + 1, col: editorStart + lineNumWidth + cursorWrapCol)
            }

            screenRow += wrappedRowCount
            if screenRow >= contentRows { break }
            lineIndex += 1
        }
        return nil
    }

    let line = state.fileLine(at: state.cursorRow)
    let cursorDisplayCol = displayColumn(for: state.cursorCol, in: line)
    let relativeCol = cursorDisplayCol - state.hScrollOffset
    guard relativeCol >= 0 && relativeCol < availWidth else { return nil }
    let row = state.cursorRow - state.scrollOffset
    guard row >= 0 && row < contentRows else { return nil }
    return (row: row + 1, col: editorStart + lineNumWidth + relativeCol)
}
