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
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        showsGutterDecorations: state.config.showGitStatus && state.config.gitDecorations.showLineChanges && state.gitLineDecorationProvider != nil,
        gutterDecorations: gutterDecorations,
        wrapLines: state.config.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.wrapLines,
        lineStyleOverlays: lineStyleOverlays,
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
