import KittyCodecs
import KittyRenderer
import KittySyntax
import KittyText

/// Renders a View hierarchy into a ScreenBuffer.
public enum ViewRenderer {

    /// Render a view into a buffer region.
    public static func render<V: View>(
        _ view: V,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext = RenderContext()
    ) {
        guard !rect.isEmpty else { return }

        switch view {
        case let text as Text:
            renderText(text, into: &buffer, in: rect, context: context)
        case let styled as StyledTextView:
            renderStyledText(styled, into: &buffer, in: rect, context: context)
        case let status as StatusBar:
            renderStatusBar(status, into: &buffer, in: rect, context: context)
        case let indicator as VerticalScrollIndicator:
            renderVerticalScrollIndicator(indicator, into: &buffer, in: rect, context: context)
        case let hIndicator as HorizontalScrollIndicator:
            renderHorizontalScrollIndicator(hIndicator, into: &buffer, in: rect, context: context)
        case let editor as TextEditor:
            renderTextEditor(editor, into: &buffer, in: rect, context: context)
        case is EmptyView:
            break
        default:
            renderGeneric(view, into: &buffer, in: rect, context: context)
        }
    }

    // MARK: - Leaf Renderers

    private static func renderText(
        _ text: Text,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        let style = context.applyTo(text.style)
        fillRow(into: &buffer, row: rect.y, col: rect.x, width: rect.width, style: style)
        buffer.write(String(text.content.prefix(rect.width)), row: rect.y, col: rect.x, style: style)
    }

    private static func renderStyledText(
        _ view: StyledTextView,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        fillRow(into: &buffer, row: rect.y, col: rect.x, width: rect.width, style: context.applyTo(.default))
        var col = rect.x
        let maxCol = rect.x + rect.width
        for span in view.spans {
            let style = context.applyTo(span.style)
            for char in span.text {
                let w = UnicodeWidth.displayWidth(of: char)
                guard col + w <= maxCol else { return }
                if w == 2 {
                    buffer[rect.y, col] = Cell(character: char, style: style, width: 2)
                    buffer[rect.y, col + 1] = Cell(character: "\0", style: style, width: 0)
                    col += 2
                } else if w == 1 {
                    buffer[rect.y, col] = Cell(character: char, style: style)
                    col += 1
                }
            }
        }
    }

    private static func renderStatusBar(
        _ bar: StatusBar,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        let style = context.applyTo(bar.style)
        let rendered = bar.render(width: rect.width)
        buffer.write(rendered, row: rect.y, col: rect.x, style: style)
    }

    private static func renderVerticalScrollIndicator(
        _ indicator: VerticalScrollIndicator,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        guard !rect.isEmpty else { return }

        let trackStyle = context.applyTo(indicator.style.trackStyle)
        let thumbStyle = context.applyTo(indicator.style.thumbStyle)
        buffer.fill(
            row: rect.y,
            col: rect.x,
            width: rect.width,
            height: rect.height,
            cell: Cell(character: indicator.style.trackCharacter, style: trackStyle)
        )

        if let thumbRect = VerticalScrollIndicatorLayout.thumbRect(for: indicator.metrics, in: rect) {
            buffer.fill(
                row: thumbRect.y,
                col: thumbRect.x,
                width: thumbRect.width,
                height: thumbRect.height,
                cell: Cell(character: indicator.style.thumbCharacter, style: thumbStyle)
            )
        }
    }

    private static func renderHorizontalScrollIndicator(
        _ indicator: HorizontalScrollIndicator,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        guard !rect.isEmpty else { return }

        let trackStyle = context.applyTo(indicator.style.trackStyle)
        let thumbStyle = context.applyTo(indicator.style.thumbStyle)
        buffer.fill(
            row: rect.y,
            col: rect.x,
            width: rect.width,
            height: rect.height,
            cell: Cell(character: indicator.style.trackCharacter, style: trackStyle)
        )

        if let thumbRect = HorizontalScrollIndicatorLayout.thumbRect(for: indicator.metrics, in: rect) {
            for col in thumbRect.x..<thumbRect.maxX {
                guard col >= rect.x, col < rect.maxX else { continue }
                buffer[thumbRect.y, col] = Cell(character: indicator.style.thumbCharacter, style: thumbStyle)
            }
        }
    }

    private static func renderScrollView(
        _ scrollView: any _ScrollViewProtocol,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        guard !rect.isEmpty else { return }

        let metrics = ScrollMetrics(
            contentLength: scrollView.contentHeight,
            viewportLength: rect.height,
            offset: scrollView.scrollOffset
        )

        if metrics.isScrollable, rect.width > 1 {
            let contentRect = Rect(
                x: rect.x,
                y: rect.y,
                width: rect.width - 1,
                height: rect.height
            )
            scrollView.contentView.render(to: &buffer, in: contentRect, context: context)

            let indicatorRect = Rect(
                x: rect.maxX - 1,
                y: rect.y,
                width: 1,
                height: rect.height
            )
            VerticalScrollIndicator(
                metrics: metrics,
                style: scrollView.scrollViewStyle.indicatorStyle
            ).render(to: &buffer, in: indicatorRect, context: context)
        } else {
            scrollView.contentView.render(to: &buffer, in: rect, context: context)
        }
    }

    private static func renderTree(
        _ tree: any _TreeViewProtocol,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        let rows = tree.rowsForRendering
        let normalStyle = context.applyTo(tree.normalStyle)
        let metrics = ScrollMetrics(
            contentLength: rows.count,
            viewportLength: rect.height,
            offset: tree.scrollOffset,
            maxOffset: max(0, rows.count - 1)
        )
        let showIndicator = tree.showsVerticalScrollIndicator && rect.width > 0 && rows.count > rect.height
        let contentWidth = max(0, rect.width - (showIndicator ? 1 : 0))

        guard !rows.isEmpty else {
            fillRect(into: &buffer, in: rect, style: normalStyle)
            return
        }

        let start = max(0, min(tree.scrollOffset, rows.count))
        let visibleCount = min(rect.height, rows.count - start)
        let indentWidth = max(0, tree.indentWidth)

        for offset in 0..<visibleCount {
            let row = rows[start + offset]
            let baseStyle = row.index == tree.selectedIndex ? tree.selectedStyle : row.style
            let style = context.applyTo(baseStyle)
            let indent = String(repeating: " ", count: row.depth * indentWidth)
            let labelText = indent + row.icon + row.label
            let line = String(labelText.prefix(contentWidth))
            fillRow(into: &buffer, row: rect.y + offset, col: rect.x, width: rect.width, style: style)
            buffer.write(line, row: rect.y + offset, col: rect.x, style: style)

            if !row.suffix.isEmpty {
                let suffixLen = row.suffix.count
                let labelLen = line.count
                let suffixCol = rect.x + contentWidth - suffixLen - 1
                if suffixCol > rect.x + labelLen {
                    let resolvedSuffixStyle = context.applyTo(row.suffixStyle)
                    buffer.write(" " + row.suffix, row: rect.y + offset, col: suffixCol, style: resolvedSuffixStyle)
                }
            }
        }

        if visibleCount < rect.height {
            for offset in visibleCount..<rect.height {
                fillRow(into: &buffer, row: rect.y + offset, col: rect.x, width: rect.width, style: normalStyle)
            }
        }

        if showIndicator {
            VerticalScrollIndicator(
                metrics: metrics,
                style: tree.scrollIndicatorStyle
            ).render(
                to: &buffer,
                in: Rect(x: rect.maxX - 1, y: rect.y, width: 1, height: rect.height),
                context: context
            )
        }
    }

    private static func renderTextEditor(
        _ editor: TextEditor,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        let editorStyle = context.applyTo(editor.editorStyle)
        let lineNumberStyle = context.applyTo(editor.lineNumberStyle)
        let currentLineStyle = context.applyTo(editor.currentLineStyle)
        let gutterWidth = TextEditorLayout.gutterWidth(for: editor)
        let gutterDecorationWidth = TextEditorLayout.gutterDecorationWidth(for: editor)
        let lineNumberColumnWidth = TextEditorLayout.lineNumberColumnWidth(for: editor)
        let contentWidth = TextEditorLayout.contentWidth(for: editor, in: rect)
        let contentMaxX = rect.x + gutterWidth + contentWidth

        guard rect.height > 0 else { return }

        if editor.wrapLines {
            var screenRow = 0
            var lineIndex = max(0, min(editor.scrollOffset, editor.lines.count))
            while screenRow < rect.height && lineIndex < editor.lines.count {
                let spans = editor.lineSpans[lineIndex]
                let totalWidth = max(1, spans.reduce(into: 0) { partial, span in
                    for char in span.text {
                        partial += UnicodeWidth.displayWidth(of: char)
                    }
                })
                let wrappedRows = max(1, contentWidth > 0 ? (totalWidth + contentWidth - 1) / contentWidth : 1)

                for wrapRow in 0..<wrappedRows where screenRow < rect.height {
                    let row = rect.y + screenRow
                    if gutterWidth > 0 {
                        if wrapRow == 0 {
                            renderGutterDecoration(
                                editor.gutterDecorations[lineIndex],
                                into: &buffer,
                                row: row,
                                col: rect.x,
                                width: gutterDecorationWidth,
                                fallbackStyle: lineNumberStyle
                            )
                            if lineNumberColumnWidth > 0 {
                                buffer.write(
                                    formattedLineNumber(lineIndex + 1, width: lineNumberColumnWidth - 1) + " ",
                                    row: row,
                                    col: rect.x + gutterDecorationWidth,
                                    style: lineNumberStyle
                                )
                            }
                        } else {
                            buffer.fill(row: row, col: rect.x, width: gutterWidth, height: 1, cell: Cell(character: " ", style: lineNumberStyle))
                        }
                    }

                    let segStart = wrapRow * max(1, contentWidth)
                    let segEnd = min(segStart + max(1, contentWidth), totalWidth)
                    var col = rect.x + gutterWidth
                    var widthPos = 0
                    for span in spans {
                        if widthPos >= segEnd { break }
                        for char in span.text {
                            let width = UnicodeWidth.displayWidth(of: char)
                            if widthPos + width > segEnd { break }
                            if widthPos >= segStart && col < contentMaxX {
                                let style = lineIndex == editor.cursorRow ? overlay(backgroundFrom: currentLineStyle, onto: span.style) : span.style
                                if width == 2 && col + 1 < contentMaxX {
                                    buffer[row, col] = Cell(character: char, style: style, width: 2)
                                    buffer[row, col + 1] = Cell(character: "\0", style: style, width: 0)
                                    col += 2
                                } else if width == 1 {
                                    buffer[row, col] = Cell(character: char, style: style)
                                    col += 1
                                }
                            }
                            widthPos += width
                        }
                    }

                    let fillStyle = lineIndex == editor.cursorRow ? currentLineStyle : editorStyle
                    while col < contentMaxX {
                        buffer[row, col] = Cell(character: " ", style: fillStyle)
                        col += 1
                    }
                    screenRow += 1
                }
                lineIndex += 1
            }

            while screenRow < rect.height {
                let row = rect.y + screenRow
                if gutterWidth > 0 {
                    renderGutterDecoration(
                        nil,
                        into: &buffer,
                        row: row,
                        col: rect.x,
                        width: gutterDecorationWidth,
                        fallbackStyle: lineNumberStyle
                    )
                    if lineNumberColumnWidth > 0 {
                        buffer.write("~", row: row, col: rect.x + gutterDecorationWidth, style: lineNumberStyle)
                        if lineNumberColumnWidth > 1 {
                            buffer.fill(
                                row: row,
                                col: rect.x + gutterDecorationWidth + 1,
                                width: lineNumberColumnWidth - 1,
                                height: 1,
                                cell: Cell(character: " ", style: lineNumberStyle)
                            )
                        }
                    }
                }
                if contentWidth > 0 {
                    buffer.fill(row: row, col: rect.x + gutterWidth, width: contentWidth, height: 1, cell: Cell(character: " ", style: editorStyle))
                }
                screenRow += 1
            }

            if let indicatorRect = TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect) {
                VerticalScrollIndicator(
                    metrics: TextEditorLayout.verticalScrollMetrics(for: editor, in: rect),
                    style: editor.verticalScrollIndicatorStyle
                ).render(to: &buffer, in: indicatorRect, context: context)
            }
            return
        }

        let startLine = max(0, min(editor.scrollOffset, editor.lines.count))
        let endLine = min(editor.lines.count, startLine + rect.height)

        for rowOffset in 0..<rect.height {
            let row = rect.y + rowOffset
            let lineIndex = startLine + rowOffset

            guard lineIndex < endLine else {
                if gutterWidth > 0 {
                    renderGutterDecoration(
                        nil,
                        into: &buffer,
                        row: row,
                        col: rect.x,
                        width: gutterDecorationWidth,
                        fallbackStyle: lineNumberStyle
                    )
                    if lineNumberColumnWidth > 0 {
                        buffer.write("~", row: row, col: rect.x + gutterDecorationWidth, style: lineNumberStyle)
                        if lineNumberColumnWidth > 1 {
                            buffer.fill(
                                row: row,
                                col: rect.x + gutterDecorationWidth + 1,
                                width: lineNumberColumnWidth - 1,
                                height: 1,
                                cell: Cell(character: " ", style: lineNumberStyle)
                            )
                        }
                    }
                }
                if contentWidth > 0 {
                    buffer.fill(row: row, col: rect.x + gutterWidth, width: contentWidth, height: 1, cell: Cell(character: " ", style: editorStyle))
                }
                continue
            }

            if gutterWidth > 0 {
                renderGutterDecoration(
                    editor.gutterDecorations[lineIndex],
                    into: &buffer,
                    row: row,
                    col: rect.x,
                    width: gutterDecorationWidth,
                    fallbackStyle: lineNumberStyle
                )
                if lineNumberColumnWidth > 0 {
                    buffer.write(
                        formattedLineNumber(lineIndex + 1, width: lineNumberColumnWidth - 1) + " ",
                        row: row,
                        col: rect.x + gutterDecorationWidth,
                        style: lineNumberStyle
                    )
                }
            }

            let spans = editor.lineSpans[lineIndex]
            renderStyledLine(
                spans: spans,
                into: &buffer,
                row: row,
                col: rect.x + gutterWidth,
                availWidth: contentWidth,
                hScrollOffset: editor.horizontalScrollOffset,
                isCurrentLine: lineIndex == editor.cursorRow,
                editorStyle: editorStyle,
                currentLineStyle: currentLineStyle
            )
        }

        if let indicatorRect = TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect) {
            VerticalScrollIndicator(
                metrics: TextEditorLayout.verticalScrollMetrics(for: editor, in: rect),
                style: editor.verticalScrollIndicatorStyle
            ).render(to: &buffer, in: indicatorRect, context: context)
        }

        // Horizontal scroll indicator (only for non-wrapped mode)
        if editor.showsHorizontalScrollIndicator, !editor.wrapLines {
            let maxWidth = editor.lines.reduce(0) { max($0, UnicodeWidth.displayWidth(of: $1)) }
            if let hRect = TextEditorLayout.horizontalScrollIndicatorRect(
                for: editor, in: rect, maxLineWidth: maxWidth
            ) {
                let hMetrics = TextEditorLayout.horizontalScrollMetrics(
                    for: editor, in: rect, maxLineWidth: maxWidth
                )
                HorizontalScrollIndicator(
                    metrics: hMetrics,
                    style: HorizontalScrollIndicatorStyle(
                        trackStyle: Style(fg: .rgb(r: 60, g: 60, b: 60), dim: true),
                        thumbStyle: Style(fg: .rgb(r: 140, g: 140, b: 140), dim: true),
                        trackCharacter: " ",
                        thumbCharacter: "\u{2501}"
                    )
                ).render(to: &buffer, in: hRect, context: context)
            }
        }
    }

    private static func formattedLineNumber(_ lineNumber: Int, width: Int) -> String {
        let digits = String(lineNumber)
        let padding = String(repeating: " ", count: max(0, width - digits.count))
        return padding + digits + " "
    }

    private static func renderGutterDecoration(
        _ decoration: TextEditor.GutterDecoration?,
        into buffer: inout ScreenBuffer,
        row: Int,
        col: Int,
        width: Int,
        fallbackStyle: Style
    ) {
        guard width > 0 else { return }

        buffer.fill(
            row: row,
            col: col,
            width: width,
            height: 1,
            cell: Cell(character: " ", style: fallbackStyle)
        )

        guard let decoration else { return }
        buffer[row, col] = Cell(character: decoration.symbol, style: decoration.style)
    }

    private static func fillRect(
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        style: Style
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        buffer.fill(row: rect.y, col: rect.x, width: rect.width, height: rect.height, cell: Cell(character: " ", style: style))
    }

    private static func fillRow(
        into buffer: inout ScreenBuffer,
        row: Int,
        col: Int,
        width: Int,
        style: Style
    ) {
        guard width > 0 else { return }
        buffer.fill(row: row, col: col, width: width, height: 1, cell: Cell(character: " ", style: style))
    }

    private static func renderStyledLine(
        spans: [StyledSpan],
        into buffer: inout ScreenBuffer,
        row: Int,
        col: Int,
        availWidth: Int,
        hScrollOffset: Int,
        isCurrentLine: Bool,
        editorStyle: Style,
        currentLineStyle: Style
    ) {
        guard availWidth > 0 else { return }
        var currentCol = col
        var currentX = 0

        for span in spans {
            for char in span.text {
                let width = UnicodeWidth.displayWidth(of: char)
                if currentX >= hScrollOffset && currentX + width <= hScrollOffset + availWidth {
                    let style = isCurrentLine ? overlay(backgroundFrom: currentLineStyle, onto: span.style) : span.style
                    if width == 2 && currentCol + 1 < col + availWidth {
                        buffer[row, currentCol] = Cell(character: char, style: style, width: 2)
                        buffer[row, currentCol + 1] = Cell(character: "\0", style: style, width: 0)
                        currentCol += 2
                    } else if width == 1 {
                        buffer[row, currentCol] = Cell(character: char, style: style)
                        currentCol += 1
                    }
                }
                currentX += width
            }
        }

        let fillStyle = isCurrentLine ? currentLineStyle : editorStyle
        while currentCol < col + availWidth {
            buffer[row, currentCol] = Cell(character: " ", style: fillStyle)
            currentCol += 1
        }
    }

    private static func overlay(backgroundFrom overlay: Style, onto base: Style) -> Style {
        var style = base
        style.bg = overlay.bg
        return style
    }

    // MARK: - Generic/Container Rendering

    private static func renderGeneric<V: View>(
        _ view: V,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        if let scrollView = view as? any _ScrollViewProtocol {
            renderScrollView(scrollView, into: &buffer, in: rect, context: context)
            return
        }

        if let tree = view as? any _TreeViewProtocol {
            renderTree(tree, into: &buffer, in: rect, context: context)
            return
        }

        if let conditional = view as? any _ConditionalViewProtocol {
            conditional.activeView.render(to: &buffer, in: rect, context: context)
            return
        }

        if let modified = view as? any _ModifiedViewProtocol {
            let mergedContext = modified.modifiedContext(from: context)
            modified.contentView.render(to: &buffer, in: rect, context: mergedContext)
            return
        }

        if let stack = view as? any _StackViewProtocol {
            renderStack(stack, into: &buffer, in: rect, context: context)
            return
        }

        if let zstack = view as? any _ZStackProtocol {
            renderZStack(zstack, into: &buffer, in: rect, context: context)
            return
        }

        if let tuple = view as? any _TupleViewProtocol {
            renderTupleView(tuple, into: &buffer, in: rect, context: context)
            return
        }

        if V.Body.self != Never.self {
            let body = view.body
            render(body, into: &buffer, in: rect, context: context)
        }
    }

    private static func renderTupleView(
        _ tuple: any _TupleViewProtocol,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        for child in tuple.childViews {
            child.render(to: &buffer, in: rect, context: context)
        }
    }

    private static func renderZStack(
        _ zstack: any _ZStackProtocol,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        for child in zstack.childViews {
            child.render(to: &buffer, in: rect, context: context)
        }
    }

    private static func renderStack(
        _ stack: any _StackViewProtocol,
        into buffer: inout ScreenBuffer,
        in rect: Rect,
        context: RenderContext
    ) {
        let children = stack.childViews
        guard !children.isEmpty else { return }

        if children.count == 1 {
            children[0].render(to: &buffer, in: rect, context: context)
            return
        }

        let segments = segments(
            totalLength: stack.axis == .vertical ? rect.height : rect.width,
            count: children.count,
            spacing: stack.spacing
        )

        for (child, segment) in zip(children, segments) {
            let childRect: Rect
            switch stack.axis {
            case .vertical:
                childRect = Rect(x: rect.x, y: rect.y + segment.offset, width: rect.width, height: segment.length)
            case .horizontal:
                childRect = Rect(x: rect.x + segment.offset, y: rect.y, width: segment.length, height: rect.height)
            }

            guard !childRect.isEmpty else { continue }
            child.render(to: &buffer, in: childRect, context: context)
        }
    }

    private static func segments(totalLength: Int, count: Int, spacing: Int) -> [(offset: Int, length: Int)] {
        guard count > 0 else { return [] }

        let resolvedSpacing = max(0, spacing)
        let totalSpacing = resolvedSpacing * max(0, count - 1)
        let availableLength = max(0, totalLength - totalSpacing)
        let baseLength = availableLength / count
        let remainder = availableLength % count

        var result: [(offset: Int, length: Int)] = []
        result.reserveCapacity(count)

        var offset = 0
        for index in 0..<count {
            let extra = index < remainder ? 1 : 0
            let length = baseLength + extra
            result.append((offset: offset, length: length))
            offset += length + resolvedSpacing
        }

        return result
    }
}

private enum _StackAxis {
    case vertical
    case horizontal
}

private protocol _TupleViewProtocol {
    var childViews: [any View] { get }
}

private protocol _ConditionalViewProtocol {
    var activeView: any View { get }
}

private protocol _ModifiedViewProtocol {
    var contentView: any View { get }
    func modifiedContext(from context: RenderContext) -> RenderContext
}

private protocol _StackViewProtocol {
    var axis: _StackAxis { get }
    var childViews: [any View] { get }
    var spacing: Int { get }
}

private protocol _ZStackProtocol {
    var childViews: [any View] { get }
}

private protocol _ScrollViewProtocol {
    var contentView: any View { get }
    var contentHeight: Int { get }
    var scrollOffset: Int { get }
    var scrollViewStyle: ScrollViewStyle { get }
}

private struct _TreeRow: Sendable {
    let depth: Int
    let icon: String
    let label: String
    let index: Int
    let style: Style
    let suffix: String
    let suffixStyle: Style
}

private protocol _TreeViewProtocol {
    var rowsForRendering: [_TreeRow] { get }
    var rowCount: Int { get }
    var normalStyle: Style { get }
    var selectedStyle: Style { get }
    var selectedIndex: Int { get }
    var indentWidth: Int { get }
    var scrollOffset: Int { get }
    var showsVerticalScrollIndicator: Bool { get }
    var scrollIndicatorStyle: VerticalScrollIndicatorStyle { get }
}

private func _childViews<Content: View>(from content: Content) -> [any View] {
    if let tuple = content as? any _TupleViewProtocol {
        return tuple.childViews
    }
    return [content]
}

extension TupleView: _TupleViewProtocol {
    fileprivate var childViews: [any View] {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .tuple {
            return mirror.children.compactMap { $0.value as? any View }
        }

        if let view = value as? any View {
            return [view]
        }

        return []
    }
}

extension ConditionalView: _ConditionalViewProtocol {
    fileprivate var activeView: any View {
        switch self {
        case let .first(view):
            view
        case let .second(view):
            view
        }
    }
}

extension ModifiedView: _ModifiedViewProtocol {
    fileprivate var contentView: any View { content }

    fileprivate func modifiedContext(from context: RenderContext) -> RenderContext {
        modifier.modifyContext(context)
    }
}

extension VStack: _StackViewProtocol {
    fileprivate var axis: _StackAxis { .vertical }
    fileprivate var childViews: [any View] { _childViews(from: content) }
}

extension HStack: _StackViewProtocol {
    fileprivate var axis: _StackAxis { .horizontal }
    fileprivate var childViews: [any View] { _childViews(from: content) }
}

extension ZStack: _ZStackProtocol {
    fileprivate var childViews: [any View] { _childViews(from: content) }
}

extension TreeView: _TreeViewProtocol {
    fileprivate var rowsForRendering: [_TreeRow] {
        visibleRows().map { row in
            let icon: String
            if row.node.isLeaf {
                icon = style.leafIcon
            } else if row.node.isExpanded {
                icon = style.expandedIcon
            } else {
                icon = style.collapsedIcon
            }

            return _TreeRow(
                depth: row.depth,
                icon: icon,
                label: label(row.node.value),
                index: row.index,
                style: rowStyle(row.node.value),
                suffix: rowSuffix(row.node.value),
                suffixStyle: rowSuffixStyle(row.node.value)
            )
        }
    }

    fileprivate var rowCount: Int {
        rowsForRendering.count
    }

    fileprivate var normalStyle: Style { style.normalStyle }
    fileprivate var selectedStyle: Style { style.selectedStyle }
    fileprivate var indentWidth: Int { style.indent }
    fileprivate var scrollIndicatorStyle: VerticalScrollIndicatorStyle { style.scrollIndicatorStyle }
}

extension ScrollView: _ScrollViewProtocol {
    fileprivate var contentView: any View { content }
    fileprivate var scrollViewStyle: ScrollViewStyle { style }
}
