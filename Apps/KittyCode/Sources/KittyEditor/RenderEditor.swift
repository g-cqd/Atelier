import AtelierText
// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_parameter_count
import KittyCodecs
import KittyFileTree
import KittyGit
public import KittyRenderer
import KittySearch
import KittyWidgets
import KittyWorkspace

@MainActor
public func renderEditorPanel(
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
    let highlights = activeHighlights(state: state, colorScheme: colorScheme)

    let wsConfig = WhitespaceRenderer.Config(
        showIndentation: state.config.whitespace.showIndentation,
        showSpaces: state.config.whitespace.showSpaces,
        showLineBreaks: state.config.whitespace.showLineBreaks,
        showUnexpected: state.config.whitespace.showUnexpected,
        selectionVisibility: selectionVisibility(from: state.config.whitespace.selectionWhitespace),
        indentationStyle: colorScheme.whitespaceIndentation,
        spaceStyle: colorScheme.whitespaceSpace,
        lineBreakStyle: colorScheme.whitespaceLineBreak,
        unexpectedStyle: colorScheme.whitespaceUnexpected
    )
    let wrapLayoutCache = state.config.editor.wrapLines ? state.wrapLayoutCacheSnapshot() : nil

    let editor = TextEditor(
        buffer: state.textBuffer,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        wrapRowOffset: state.wrapRowOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        showsGutterDecorations: state.config.git.enabled
            && state.config.git.decorations.showLineChanges
            && state.gitLineDecorationProvider != nil,
        gutterDecorations: gutterDecorations,
        wrapLines: state.config.editor.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.editor.wrapLines,
        lineStyleOverlays: lineStyleOverlays,
        highlights: highlights,
        editorStyle: colorScheme.editorText,
        lineNumberStyle: colorScheme.lineNumber,
        currentLineStyle: colorScheme.editorCursorLine,
        verticalScrollIndicatorStyle: colorScheme.verticalScrollIndicator,
        horizontalScrollIndicatorStyle: colorScheme.horizontalScrollIndicator,
        modeShowsCursor: state.mode == .editor,
        maxLineWidth: state.maxLineWidth,
        tabSize: state.config.editor.tabSize,
        whitespaceConfig: wsConfig,
        wrapLayoutCache: wrapLayoutCache
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
private func activeHighlights(
    state: EditorState,
    colorScheme: EditorState.ColorScheme
) -> [Int: [TextHighlight]] {
    var highlights: [Int: [TextHighlight]] = [:]

    if let selection = state.selection, !selection.isCollapsed {
        let (start, end) = selection.ordered
        let style = colorScheme.selection

        if start.row == end.row {
            if end.col > start.col {
                highlights[start.row] = [
                    TextHighlight(
                        range: start.col ... end.col - 1, role: .userSelection, style: style)
                ]
            }
        } else {
            let firstLineLength = state.fileLine(at: start.row).count
            highlights[start.row] = [
                TextHighlight(
                    range: start.col ... firstLineLength, role: .userSelection, style: style)
            ]

            for row in (start.row + 1) ..< end.row {
                let lineLength = state.fileLine(at: row).count
                highlights[row] = [
                    TextHighlight(range: 0 ... lineLength, role: .userSelection, style: style)
                ]
            }

            if end.row > start.row && end.col > 0 {
                highlights[end.row] = [
                    TextHighlight(range: 0 ... end.col - 1, role: .userSelection, style: style)
                ]
            }
        }
    }

    if state.config.git.enabled, state.config.git.decorations.showLineChanges,
        let emphasis = state.bufferManager.activeBuffer?.gitLineDecorations.emphasis, !emphasis.isEmpty
    {
        let style = Style(fg: colorScheme.gitModified.fg, bold: true)
        for (row, ranges) in emphasis {
            highlights[row, default: []]
                .append(contentsOf: ranges.map { TextHighlight(range: $0, role: .changedText, style: style) })
        }
    }

    if let search = state.inFileSearch {
        for (index, match) in search.matches.enumerated() where match.colEnd > match.colStart {
            let role: TextHighlight.Role =
                index == search.activeMatchIndex ? .activeSearchMatch : .searchMatch
            let style =
                index == search.activeMatchIndex
                ? colorScheme.activeSearchMatch : colorScheme.searchMatch
            let highlight = TextHighlight(
                range: match.colStart ... (match.colEnd - 1), role: role, style: style)
            highlights[match.row, default: []].append(highlight)
        }
    }

    return highlights
}

private func selectionVisibility(
    from config: KittyConfig.WhitespaceVisibility
) -> WhitespaceRenderer.SelectionVisibility {
    switch config {
        case .none: return .none
        case .indentation: return .indentation
        case .all: return .all
        case .boundary: return .boundary
    }
}
