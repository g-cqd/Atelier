import AtelierText
// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_parameter_count
import KittyCodecs
import KittyFileTree
import KittyGit
public import KittyRenderer
import KittySearch
import KittyTerminal
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

    var editor = TextEditor(
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
    if let chrome = pipeline.chrome {
        // Backgrounds and bars are pixels under the cells; the cells keep foregrounds only.
        pipeline.chromeElements.append(
            contentsOf: pixelEditorElements(editor: editor, rect: rect, state: state, cell: chrome.cell))
        editor.currentLineStyle = Style(fg: editor.currentLineStyle.fg)
        editor.gutterDecorations = editor.gutterDecorations.mapValues {
            TextEditor.GutterDecoration(symbol: " ", style: $0.style)
        }
        editor.highlights = editor.highlights.mapValues { highlights in
            highlights.map { highlight in
                var cellHighlight = highlight
                cellHighlight.style.bg = .default
                return cellHighlight
            }
        }
        editor.verticalScrollIndicatorStyle = VerticalScrollIndicatorStyle(
            trackStyle: .default, thumbStyle: .default, trackCharacter: " ", thumbCharacter: " ")
    }
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

    var result: [Int: TextEditor.GutterDecoration] = [:]
    for lineIndex in visibleRows(of: state) {
        guard let color = decorations[lineIndex] else { continue }
        result[lineIndex] = TextEditor.GutterDecoration(
            symbol: gutterSymbol(for: color),
            style: colorScheme.gitStatusStyle(for: color)
        )
    }
    return result
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

/// The rows a frame can show, the only ones the renderer reads highlights and gutter marks for.
@MainActor
private func visibleRows(of state: EditorState) -> Range<Int> {
    let first = max(0, state.scrollOffset)
    return first ..< min(state.fileLineCount, first + max(state.lastRenderRows, 1) + 1)
}

/// Per-line highlights for the rows on screen only: a selection spanning a whole document, thousands of git
/// emphasis ranges or a common-word search would otherwise size every frame by the document.
@MainActor
private func activeHighlights(
    state: EditorState,
    colorScheme: EditorState.ColorScheme
) -> [Int: [TextHighlight]] {
    var highlights: [Int: [TextHighlight]] = [:]
    let visible = visibleRows(of: state)

    if let selection = state.selection, !selection.isCollapsed {
        let (start, end) = selection.ordered
        let style = colorScheme.selection

        if start.row == end.row {
            if end.col > start.col, visible.contains(start.row) {
                highlights[start.row] = [
                    TextHighlight(range: start.col ... end.col - 1, role: .userSelection, style: style)
                ]
            }
        } else {
            if visible.contains(start.row) {
                let firstLineLength = state.fileLine(at: start.row).count
                highlights[start.row] = [
                    TextHighlight(
                        range: min(start.col, firstLineLength) ... firstLineLength, role: .userSelection, style: style)
                ]
            }
            for row in ((start.row + 1) ..< end.row).clamped(to: visible) {
                let lineLength = state.fileLine(at: row).count
                highlights[row] = [TextHighlight(range: 0 ... lineLength, role: .userSelection, style: style)]
            }
            if end.row > start.row, end.col > 0, visible.contains(end.row) {
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
        for row in visible {
            guard let ranges = emphasis[row] else { continue }
            highlights[row, default: []]
                .append(contentsOf: ranges.map { TextHighlight(range: $0, role: .changedText, style: style) })
        }
    }

    if let search = state.inFileSearch {
        for (index, match) in search.matches.enumerated()
        where match.colEnd > match.colStart && visible.contains(match.row) {
            let isActive = index == search.activeMatchIndex
            highlights[match.row, default: []]
                .append(
                    TextHighlight(
                        range: match.colStart ... (match.colEnd - 1),
                        role: isActive ? .activeSearchMatch : .searchMatch,
                        style: isActive ? colorScheme.activeSearchMatch : colorScheme.searchMatch))
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

// MARK: - Pixel chrome

/// The editor panel's decorations as pixels: selection and search bands and the current line as scaled fills,
/// the scroll bar as a track and a thumb placed to the pixel, git gutter marks as colour bars.
/// - Complexity: O(visible rows + visible search hits)
@MainActor
private func pixelEditorElements(
    editor: TextEditor, rect: Rect, state: EditorState, cell: TerminalCapabilities.CellPixelSize
) -> [ChromeElement] {
    var elements: [ChromeElement] = []
    let gutterWidth = TextEditorLayout.gutterWidth(for: editor)
    let contentWidth = TextEditorLayout.contentWidth(for: editor, in: rect)
    let contentX = rect.x + gutterWidth
    let tabSize = editor.tabSize
    let firstLine = max(0, editor.scrollOffset)
    let visible = firstLine ..< min(editor.lineCount, firstLine + rect.height)
    func screenRow(_ line: Int) -> Int { rect.y + line - firstLine }
    func column(_ line: String, at index: Int) -> Int {
        let width = TextDisplayMetrics.displayWidth(of: String(line.prefix(max(0, index))), tabSize: tabSize)
        return width - editor.horizontalScrollOffset
    }
    func band(line: Int, from start: Int, to end: Int, color: ColorRGB) {
        let lower = max(0, start)
        let upper = min(contentWidth, end)
        guard upper > lower, contentWidth > 0 else { return }
        elements.append(
            .fill(row: screenRow(line), column: contentX + lower, columns: upper - lower, rows: 1, color: color))
    }

    // Line geometry is one row per line here; wrapped lines keep their cell backgrounds.
    if !editor.wrapLines {
        if editor.modeShowsCursor, visible.contains(editor.cursorRow), let color = ColorRGB(editor.currentLineStyle.bg)
        {
            band(line: editor.cursorRow, from: 0, to: contentWidth, color: color)
        }
        if let selection = state.selection, !selection.isCollapsed, let color = ColorRGB(state.colorScheme.selection.bg)
        {
            let (start, end) = selection.ordered
            let first = max(start.row, visible.lowerBound)
            let last = min(end.row, visible.upperBound - 1)
            for line in first ..< max(first, last + 1) {
                let text = state.fileLine(at: line)
                let from = line == start.row ? column(text, at: start.col) : 0
                let to = line == end.row ? column(text, at: end.col) : column(text, at: text.count) + 1
                band(line: line, from: from, to: to, color: color)
            }
        }
        if let search = state.inFileSearch {
            for (index, match) in search.matches.enumerated() where visible.contains(match.row) {
                let style =
                    index == search.activeMatchIndex
                    ? state.colorScheme.activeSearchMatch : state.colorScheme.searchMatch
                guard let color = ColorRGB(style.bg) else { continue }
                let text = state.fileLine(at: match.row)
                band(
                    line: match.row, from: column(text, at: match.colStart), to: column(text, at: match.colEnd),
                    color: color)
            }
        }
        if editor.showsGutterDecorations, gutterWidth > 0 {
            let width = max(2, cell.width / 3)
            for line in visible {
                guard let decoration = editor.gutterDecorations[line], let color = ColorRGB(decoration.style.fg) else {
                    continue
                }
                elements.append(
                    .bar(
                        row: screenRow(line), column: rect.x, widthPixels: width, heightPixels: cell.height,
                        color: color,
                        xOffset: max(0, (cell.width - width) / 2), yOffset: 0))
            }
        }
    }

    elements.append(contentsOf: pixelScrollBar(editor: editor, rect: rect, cell: cell))
    return elements
}

/// The vertical scroll bar as a one-pixel track and a thumb whose height and position are pixel-exact.
@MainActor
private func pixelScrollBar(editor: TextEditor, rect: Rect, cell: TerminalCapabilities.CellPixelSize)
    -> [ChromeElement]
{
    var elements: [ChromeElement] = []
    if let indicatorRect = TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect), indicatorRect.height > 0
    {
        let metrics = TextEditorLayout.verticalScrollMetrics(for: editor, in: rect)
        let trackPixels = indicatorRect.height * cell.height
        if let track = ColorRGB(editor.verticalScrollIndicatorStyle.trackStyle.fg) {
            elements.append(
                .bar(
                    row: indicatorRect.y, column: indicatorRect.x, widthPixels: 1, heightPixels: trackPixels,
                    color: track,
                    xOffset: cell.width / 2, yOffset: 0))
        }
        if metrics.isScrollable, metrics.contentLength > 0,
            let thumb = ColorRGB(editor.verticalScrollIndicatorStyle.thumbStyle.fg)
        {
            let thumbPixels = max(cell.height, trackPixels * metrics.viewportLength / metrics.contentLength)
            let travel = max(0, trackPixels - thumbPixels)
            let origin = metrics.maxOffset > 0 ? travel * min(metrics.offset, metrics.maxOffset) / metrics.maxOffset : 0
            let width = max(2, cell.width / 2)
            elements.append(
                .bar(
                    row: indicatorRect.y + origin / cell.height, column: indicatorRect.x, widthPixels: width,
                    heightPixels: thumbPixels, color: thumb, xOffset: max(0, (cell.width - width) / 2),
                    yOffset: origin % cell.height))
        }
    }
    return elements
}
