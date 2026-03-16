import KittyCodecs
import KittyText

@MainActor
func jumpWordForward(state: EditorState) {
    TextNavigation.moveWordForward(cursor: &state.textCursor, in: state.textBuffer)
}

@MainActor
func jumpWordBackward(state: EditorState) {
    TextNavigation.moveWordBackward(cursor: &state.textCursor, in: state.textBuffer)
}

@MainActor
func ensureEditorVisible(_ state: EditorState, contentRows: Int = 20, availWidth: Int = 80) {
    guard state.config.editor.wrapLines else {
        TextNavigation.ensureVisible(
            cursor: &state.textCursor,
            visibleRows: contentRows,
            visibleCols: availWidth,
            wrapLines: false
        )
        return
    }

    let contentWidth = max(1, availWidth)
    state.buildWrapCache(contentWidth: contentWidth)

    let currentVisualTop = state.visualRowOffset(forLine: state.scrollOffset) + state.wrapRowOffset
    let line = state.fileLine(at: state.cursorRow)
    let displayColumn = TextDisplayMetrics.displayColumn(
        forCharacterOffset: state.cursorCol,
        in: line,
        tabSize: state.config.editor.tabSize
    )
    let cursorWrapRow = wrappedCursorRow(
        forDisplayColumn: displayColumn,
        in: line,
        contentWidth: contentWidth,
        tabSize: state.config.editor.tabSize
    )
    let cursorVisualRow = state.visualRowOffset(forLine: state.cursorRow) + cursorWrapRow

    let nextVisualTop: Int
    if cursorVisualRow < currentVisualTop {
        nextVisualTop = cursorVisualRow
    } else if cursorVisualRow >= currentVisualTop + contentRows {
        nextVisualTop = cursorVisualRow - contentRows + 1
    } else {
        state.hScrollOffset = 0
        return
    }

    let nextPosition = state.lineAndWrapRowOffset(forVisualRowOffset: nextVisualTop)
    state.scrollOffset = nextPosition.line
    state.wrapRowOffset = nextPosition.wrapRow
    state.hScrollOffset = 0
}

private func wrappedCursorRow(
    forDisplayColumn displayColumn: Int,
    in line: String,
    contentWidth: Int,
    tabSize: Int
) -> Int {
    guard contentWidth > 0 else { return 0 }

    let rowStarts = wrappedRowStartColumns(for: line, contentWidth: contentWidth, tabSize: tabSize)
    let totalWidth = max(0, TextDisplayMetrics.displayWidth(of: line, tabSize: tabSize))
    let clampedDisplayColumn = max(0, displayColumn)

    for rowIndex in rowStarts.indices {
        let end = rowIndex + 1 < rowStarts.count ? rowStarts[rowIndex + 1] : totalWidth
        if clampedDisplayColumn < end || rowIndex == rowStarts.count - 1 {
            return rowIndex
        }
    }

    return 0
}

private func wrappedRowStartColumns(for line: String, contentWidth: Int, tabSize: Int) -> [Int] {
    guard contentWidth > 0 else { return [0] }

    var starts = [0]
    var currentRowWidth = 0
    let resolvedTabSize = max(1, tabSize)

    for char in line {
        let width =
            char == "\t"
            ? resolvedTabSize - (currentRowWidth % resolvedTabSize)
            : UnicodeWidth.displayWidth(of: char)
        guard width > 0 else { continue }

        if currentRowWidth > 0, currentRowWidth + width > contentWidth {
            starts.append(starts[starts.count - 1] + currentRowWidth)
            currentRowWidth = 0
        }

        currentRowWidth += width
    }

    return starts
}
