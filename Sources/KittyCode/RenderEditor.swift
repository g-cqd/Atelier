import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func renderEditorPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    editorStart: Int,
    editorWidth: Int,
    contentStartRow: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    if state.bufferManager.isEmpty && state.isFileEmpty {
        renderEmptyEditor(
            pipeline: pipeline,
            editorStart: editorStart,
            editorWidth: editorWidth,
            contentStartRow: contentStartRow,
            contentRows: contentRows,
            colorScheme: colorScheme
        )
        return nil
    }

    let gutterDecorations = activeGutterDecorations(state: state, colorScheme: colorScheme)
    let lineStyleOverlays = activeLineStyleOverlays(state: state, colorScheme: colorScheme)
    let selectionRanges = activeSelectionRanges(state: state)

    let wsConfig = WhitespaceRenderer.Config(
        showIndentation: state.config.whitespace.showIndentation,
        showSpaces: state.config.whitespace.showSpaces,
        showLineBreaks: state.config.whitespace.showLineBreaks,
        showUnexpected: state.config.whitespace.showUnexpected,
        indentationStyle: colorScheme.whitespaceIndentation,
        spaceStyle: colorScheme.whitespaceSpace,
        lineBreakStyle: colorScheme.whitespaceLineBreak,
        unexpectedStyle: colorScheme.whitespaceUnexpected
    )

    let editor = TextEditor(
        buffer: state.textBuffer,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        wrapRowOffset: state.wrapRowOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        showsGutterDecorations: state.config.git.enabled && state.config.git.decorations.showLineChanges && state.gitLineDecorationProvider != nil,
        gutterDecorations: gutterDecorations,
        wrapLines: state.config.editor.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.editor.wrapLines,
        lineStyleOverlays: lineStyleOverlays,
        selectionRanges: selectionRanges,
        selectionStyle: colorScheme.selection,
        editorStyle: colorScheme.editorText,
        lineNumberStyle: colorScheme.lineNumber,
        currentLineStyle: colorScheme.editorCursorLine,
        verticalScrollIndicatorStyle: colorScheme.verticalScrollIndicator,
        horizontalScrollIndicatorStyle: colorScheme.horizontalScrollIndicator,
        modeShowsCursor: state.mode == .editor,
        maxLineWidth: state.maxLineWidth,
        tabSize: state.config.editor.tabSize,
        whitespaceConfig: wsConfig
    )

    let rect = Rect(x: editorStart, y: contentStartRow, width: editorWidth, height: contentRows)
    editor.render(to: &pipeline.buffer, in: rect)
    guard let cursor = TextEditorLayout.cursorPosition(for: editor, in: rect) else {
        return nil
    }
    return (row: cursor.row, col: cursor.col)
}

@MainActor
private func activeGutterDecorations(
    state: EditorState,
    colorScheme: EditorState.ColorScheme
) -> [Int: TextEditor.GutterDecoration] {
    guard let decorations = state.bufferManager.activeBuffer?.gitLineDecorations.markers,
          !decorations.isEmpty
    else {
        return [:]
    }

    return decorations.reduce(into: [Int: TextEditor.GutterDecoration]()) { result, entry in
        let (lineIndex, color) = entry
        result[lineIndex] = TextEditor.GutterDecoration(
            symbol: gutterSymbol(for: color),
            style: colorScheme.gitStatusStyle(for: color)
        )
    }
}

private func gutterSymbol(for color: FileStatusColor) -> Character {
    switch color {
    case .added: return "+"
    case .modified: return "~"
    case .untracked: return "?"
    case .deleted: return "-"
    case .conflicted, .clean: return "!"
    }
}

@MainActor
private func activeSelectionRanges(state: EditorState) -> [Int: ClosedRange<Int>] {
    guard let selection = state.selection, !selection.isCollapsed else { return [:] }
    let (start, end) = selection.ordered
    var ranges: [Int: ClosedRange<Int>] = [:]

    if start.row == end.row {
        ranges[start.row] = start.col...end.col - 1
    } else {
        let firstLineLength = state.fileLine(at: start.row).count
        ranges[start.row] = start.col...firstLineLength

        for row in (start.row + 1)..<end.row {
            let lineLength = state.fileLine(at: row).count
            ranges[row] = 0...lineLength
        }

        if end.row > start.row {
            ranges[end.row] = 0...end.col - 1
        }
    }

    return ranges
}
