import KittyText

/// Shared layout calculations for `TextEditor` rendering and cursor placement.
public enum TextEditorLayout {
    public struct CursorPosition: Sendable, Equatable {
        public let row: Int
        public let col: Int

        public init(row: Int, col: Int) {
            self.row = row
            self.col = col
        }
    }

    public static func gutterWidth(for editor: TextEditor) -> Int {
        gutterDecorationWidth(for: editor) + lineNumberColumnWidth(for: editor)
    }

    public static func contentWidth(for editor: TextEditor, in rect: Rect) -> Int {
        max(
            0,
            rect.width - gutterWidth(for: editor)
                - verticalScrollIndicatorWidth(for: editor, in: rect))
    }

    public static func gutterDecorationWidth(for editor: TextEditor) -> Int {
        editor.showsGutterDecorations ? 2 : 0
    }

    public static func lineNumberColumnWidth(for editor: TextEditor) -> Int {
        editor.showLineNumbers ? max(3, editor.lineNumberWidth + 1) : 0
    }

    public static func verticalScrollMetrics(for editor: TextEditor, in rect: Rect) -> ScrollMetrics
    {
        if editor.wrapLines {
            let contentWidth = max(1, contentWidth(for: editor, in: rect))
            let visualRowCount = totalWrappedRowCount(for: editor, contentWidth: contentWidth)
            let visualOffset = visualRowOffset(
                forLineOffset: editor.scrollOffset,
                editor: editor,
                contentWidth: contentWidth
            )
            let maxOffset = visualRowOffset(
                forLineOffset: max(0, editor.lineCount - 1),
                editor: editor,
                contentWidth: contentWidth
            )
            return ScrollMetrics(
                contentLength: visualRowCount,
                viewportLength: rect.height,
                offset: visualOffset + editor.wrapRowOffset,
                maxOffset: maxOffset
            )
        }

        return ScrollMetrics(
            contentLength: editor.lineCount,
            viewportLength: rect.height,
            offset: editor.scrollOffset,
            maxOffset: max(0, editor.lineCount - 1)
        )
    }

    public static func verticalScrollIndicatorRect(
        for editor: TextEditor,
        in rect: Rect
    ) -> Rect? {
        guard verticalScrollIndicatorWidth(for: editor, in: rect) > 0 else { return nil }
        return Rect(x: rect.maxX - 1, y: rect.y, width: 1, height: rect.height)
    }

    public static func scrollGripOffset(
        for editor: TextEditor,
        in rect: Rect,
        pointerRow: Int
    ) -> Int? {
        guard let indicatorRect = verticalScrollIndicatorRect(for: editor, in: rect) else {
            return nil
        }
        return VerticalScrollIndicatorLayout.gripOffset(
            for: verticalScrollMetrics(for: editor, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow
        )
    }

    public static func scrollOffset(
        for editor: TextEditor,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> Int {
        let (line, _) = scrollPosition(
            for: editor, in: rect, pointerRow: pointerRow, gripOffset: gripOffset)
        return line
    }

    public static func scrollPosition(
        for editor: TextEditor,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> (lineOffset: Int, wrapRowOffset: Int) {
        guard let indicatorRect = verticalScrollIndicatorRect(for: editor, in: rect) else {
            return (editor.scrollOffset, editor.wrapRowOffset)
        }

        let metrics = verticalScrollMetrics(for: editor, in: rect)
        let nextVisualOffset = VerticalScrollIndicatorLayout.offset(
            for: metrics,
            in: indicatorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )

        guard editor.wrapLines else { return (nextVisualOffset, 0) }
        let wrappedContentWidth = max(1, contentWidth(for: editor, in: rect))
        let (line, wrapRow) = lineAndWrapRowOffset(
            forVisualRowOffset: nextVisualOffset,
            editor: editor,
            contentWidth: wrappedContentWidth
        )
        return (line, wrapRow)
    }

    public static func cursorPosition(for editor: TextEditor, in rect: Rect) -> CursorPosition? {
        guard editor.modeShowsCursor else { return nil }
        guard rect.height > 0 else { return nil }
        guard editor.cursorRow >= 0 && editor.cursorRow < editor.lineCount else { return nil }

        let gutterWidth = gutterWidth(for: editor)
        let contentWidth = max(1, contentWidth(for: editor, in: rect))
        let startLine = max(0, min(editor.scrollOffset, editor.lineCount))
        guard editor.cursorRow >= startLine else { return nil }

        let line = editor.line(at: editor.cursorRow)
        let displayColumn = TextDisplayMetrics.displayColumn(
            forCharacterOffset: editor.cursorCol, in: line, tabSize: editor.tabSize)

        if editor.wrapLines {
            let startVisualRow = visualRowOffset(
                forLineOffset: startLine,
                editor: editor,
                contentWidth: contentWidth
            ) + editor.wrapRowOffset
            let (wrapRow, wrapColumn) = wrappedRowPosition(
                forDisplayColumn: displayColumn,
                in: line,
                contentWidth: contentWidth,
                tabSize: editor.tabSize
            )
            let cursorVisualRow = visualRowOffset(
                forLineOffset: editor.cursorRow,
                editor: editor,
                contentWidth: contentWidth
            ) + wrapRow
            let row = cursorVisualRow - startVisualRow
            guard row >= 0 else { return nil }
            guard row < rect.height else { return nil }
            return CursorPosition(
                row: rect.y + row,
                col: rect.x + gutterWidth + min(wrapColumn, contentWidth - 1)
            )
        }

        let row = editor.cursorRow - startLine
        let relativeColumn = displayColumn - editor.horizontalScrollOffset
        guard row >= 0 && row < rect.height else { return nil }
        guard relativeColumn >= 0 && relativeColumn < contentWidth else { return nil }
        return CursorPosition(
            row: rect.y + row,
            col: rect.x + gutterWidth + relativeColumn
        )
    }

    public static func textPosition(
        for editor: TextEditor,
        in rect: Rect,
        row: Int,
        col: Int
    ) -> TextPosition? {
        guard rect.height > 0 else { return nil }
        guard row >= rect.y && row < rect.maxY else { return nil }
        if let indicatorRect = verticalScrollIndicatorRect(for: editor, in: rect),
            col >= indicatorRect.x && col < indicatorRect.maxX
        {
            return nil
        }

        let gutterWidth = gutterWidth(for: editor)
        let contentWidth = max(1, contentWidth(for: editor, in: rect))
        let relativeRow = row - rect.y
        let relativeColumn = max(0, col - rect.x - gutterWidth)
        let displayColumn = min(relativeColumn, contentWidth - 1)
        let startLine = max(0, min(editor.scrollOffset, editor.lineCount))

        if editor.wrapLines {
            let startVisualRow = visualRowOffset(
                forLineOffset: startLine,
                editor: editor,
                contentWidth: contentWidth
            ) + editor.wrapRowOffset
            let targetVisualRow = startVisualRow + relativeRow
            guard targetVisualRow >= 0 else { return nil }
            guard targetVisualRow < totalWrappedRowCount(for: editor, contentWidth: contentWidth)
            else { return nil }

            let (lineIndex, wrapRow) = lineAndWrapRowOffset(
                forVisualRowOffset: targetVisualRow,
                editor: editor,
                contentWidth: contentWidth
            )
            let line = editor.line(at: lineIndex)
            let rowStarts = wrappedRowStartColumns(
                for: line, contentWidth: contentWidth, tabSize: editor.tabSize)
            let rowStart = rowStarts[min(max(0, wrapRow), max(0, rowStarts.count - 1))]
            let wrappedDisplayColumn = rowStart + displayColumn
            return TextPosition(
                row: lineIndex,
                col: TextDisplayMetrics.characterOffset(
                    forDisplayColumn: wrappedDisplayColumn,
                    in: line,
                    tabSize: editor.tabSize
                )
            )
        }

        let lineIndex = startLine + relativeRow
        guard lineIndex >= 0 && lineIndex < editor.lineCount else { return nil }
        let line = editor.line(at: lineIndex)
        return TextPosition(
            row: lineIndex,
            col: TextDisplayMetrics.characterOffset(
                forDisplayColumn: displayColumn + editor.horizontalScrollOffset,
                in: line,
                tabSize: editor.tabSize
            )
        )
    }

    // MARK: - Horizontal Scroll

    public static func horizontalScrollMetrics(for editor: TextEditor, maxLineWidth: Int)
        -> ScrollMetrics
    {
        let contentWidth = max(1, maxLineWidth + 1)
        return ScrollMetrics(
            contentLength: contentWidth,
            viewportLength: 1,  // computed per-rect below
            offset: editor.horizontalScrollOffset
        )
    }

    public static func needsHorizontalScrollIndicator(
        for editor: TextEditor, in rect: Rect, maxLineWidth: Int
    ) -> Bool {
        guard editor.showsHorizontalScrollIndicator, !editor.wrapLines else { return false }
        guard rect.width > 0, rect.height > 1 else { return false }
        let gutterW = gutterWidth(for: editor)
        let vsiW = verticalScrollIndicatorWidth(for: editor, in: rect)
        let availWidth = max(0, rect.width - gutterW - vsiW)
        return maxLineWidth + 1 > availWidth
    }

    public static func horizontalScrollIndicatorRect(
        for editor: TextEditor,
        in rect: Rect,
        maxLineWidth: Int
    ) -> Rect? {
        guard needsHorizontalScrollIndicator(for: editor, in: rect, maxLineWidth: maxLineWidth)
        else { return nil }
        let gutterW = gutterWidth(for: editor)
        let vsiW = verticalScrollIndicatorWidth(for: editor, in: rect)
        let trackWidth = max(0, rect.width - gutterW - vsiW)
        guard trackWidth > 0 else { return nil }
        return Rect(x: rect.x + gutterW, y: rect.maxY - 1, width: trackWidth, height: 1)
    }

    public static func horizontalScrollMetrics(
        for editor: TextEditor,
        in rect: Rect,
        maxLineWidth: Int
    ) -> ScrollMetrics {
        let gutterW = gutterWidth(for: editor)
        let vsiW = verticalScrollIndicatorWidth(for: editor, in: rect)
        let availWidth = max(0, rect.width - gutterW - vsiW)
        let contentLength = max(1, maxLineWidth + 1)
        return ScrollMetrics(
            contentLength: contentLength,
            viewportLength: availWidth,
            offset: editor.horizontalScrollOffset,
            maxOffset: max(0, contentLength - availWidth)
        )
    }

    private static func verticalScrollIndicatorWidth(for editor: TextEditor, in rect: Rect) -> Int {
        needsScrollIndicator(for: editor, in: rect) ? 1 : 0
    }

    private static func needsScrollIndicator(for editor: TextEditor, in rect: Rect) -> Bool {
        guard editor.showsVerticalScrollIndicator, rect.width > 0, rect.height > 0 else {
            return false
        }
        if editor.wrapLines {
            let gutter = gutterWidth(for: editor)
            let pessimisticContentWidth = max(1, rect.width - gutter - 1)
            let visualRows = totalWrappedRowCount(
                for: editor, contentWidth: pessimisticContentWidth)
            return visualRows > rect.height
        }
        return editor.lineCount > rect.height
    }

    private static func wrappedRowCount(for line: String, contentWidth: Int, tabSize: Int = 4)
        -> Int
    {
        guard contentWidth > 0 else { return 1 }
        return wrappedRowStartColumns(for: line, contentWidth: contentWidth, tabSize: tabSize).count
    }

    private static func totalWrappedRowCount(for editor: TextEditor, contentWidth: Int) -> Int {
        if let cache = wrapLayoutCache(for: editor, contentWidth: contentWidth) {
            return cache.totalRowCount
        }

        return (0..<editor.lineCount).reduce(into: 0) { total, lineIndex in
            total += wrappedRowCount(
                for: editor.line(at: lineIndex), contentWidth: contentWidth, tabSize: editor.tabSize
            )
        }
    }

    private static func visualRowOffset(
        forLineOffset lineOffset: Int,
        editor: TextEditor,
        contentWidth: Int
    ) -> Int {
        guard editor.lineCount > 0 else { return 0 }

        let clampedLineOffset = min(max(0, lineOffset), max(0, editor.lineCount - 1))
        if let cache = wrapLayoutCache(for: editor, contentWidth: contentWidth),
            cache.visualOffsets.indices.contains(clampedLineOffset)
        {
            return cache.visualOffsets[clampedLineOffset]
        }

        var visualOffset = 0

        for lineIndex in 0..<clampedLineOffset {
            visualOffset += wrappedRowCount(
                for: editor.line(at: lineIndex), contentWidth: contentWidth, tabSize: editor.tabSize
            )
        }

        return visualOffset
    }

    private static func lineOffset(
        forVisualRowOffset visualRowOffset: Int,
        editor: TextEditor,
        contentWidth: Int
    ) -> Int {
        lineAndWrapRowOffset(
            forVisualRowOffset: visualRowOffset, editor: editor, contentWidth: contentWidth
        ).0
    }

    private static func lineAndWrapRowOffset(
        forVisualRowOffset visualRowOffset: Int,
        editor: TextEditor,
        contentWidth: Int
    ) -> (Int, Int) {
        guard editor.lineCount > 0 else { return (0, 0) }

        let resolvedVisualRowOffset = max(0, visualRowOffset)
        if let cache = wrapLayoutCache(for: editor, contentWidth: contentWidth) {
            var low = 0
            var high = cache.visualOffsets.count - 1

            while low <= high {
                let mid = (low + high) / 2
                if cache.visualOffsets[mid] <= resolvedVisualRowOffset {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }

            let lineIndex = max(0, min(high, cache.visualOffsets.count - 1))
            let lineStart = cache.visualOffsets[lineIndex]
            let rowCount =
                cache.lineWrapCounts.indices.contains(lineIndex)
                ? cache.lineWrapCounts[lineIndex] : 1
            return (
                lineIndex,
                min(max(0, resolvedVisualRowOffset - lineStart), max(0, rowCount - 1))
            )
        }

        var currentVisualRow = 0

        for lineIndex in 0..<editor.lineCount {
            let line = editor.line(at: lineIndex)
            let rowCount = wrappedRowCount(
                for: line, contentWidth: contentWidth, tabSize: editor.tabSize)
            let nextVisualRow = currentVisualRow + rowCount
            if resolvedVisualRowOffset < nextVisualRow {
                return (lineIndex, resolvedVisualRowOffset - currentVisualRow)
            }
            currentVisualRow = nextVisualRow
        }

        return (max(0, editor.lineCount - 1), 0)
    }

    static func wrappedRowStartColumns(for line: String, contentWidth: Int, tabSize: Int = 4)
        -> [Int]
    {
        guard contentWidth > 0 else { return [0] }

        var starts = [0]
        var rowStartColumn = 0
        var currentRowWidth = 0

        for char in line {
            let absoluteColumn = rowStartColumn + currentRowWidth
            let width = displayWidth(of: char, atColumn: absoluteColumn, tabSize: tabSize)
            guard width > 0 else { continue }

            if currentRowWidth > 0, currentRowWidth + width > contentWidth {
                rowStartColumn += currentRowWidth
                starts.append(rowStartColumn)
                currentRowWidth = 0
            }

            currentRowWidth += width
        }

        return starts
    }

    private static func wrappedRowPosition(
        forDisplayColumn displayColumn: Int,
        in line: String,
        contentWidth: Int,
        tabSize: Int = 4
    ) -> (row: Int, column: Int) {
        let rowStarts = wrappedRowStartColumns(
            for: line, contentWidth: contentWidth, tabSize: tabSize)
        let totalWidth = max(0, TextDisplayMetrics.displayWidth(of: line, tabSize: tabSize))
        let clampedDisplayColumn = max(0, displayColumn)

        for rowIndex in rowStarts.indices {
            let start = rowStarts[rowIndex]
            let end = rowIndex + 1 < rowStarts.count ? rowStarts[rowIndex + 1] : totalWidth
            if clampedDisplayColumn < end || rowIndex == rowStarts.count - 1 {
                return (rowIndex, clampedDisplayColumn - start)
            }
        }

        return (0, 0)
    }

    private static func displayWidth(of char: Character, atColumn column: Int, tabSize: Int) -> Int
    {
        if char == "\t" {
            let ts = max(1, tabSize)
            return ts - (column % ts)
        }
        return UnicodeWidth.displayWidth(of: char)
    }

    private static func wrapLayoutCache(for editor: TextEditor, contentWidth: Int)
        -> TextEditor.WrapLayoutCache?
    {
        guard let cache = editor.wrapLayoutCache else { return nil }
        guard cache.contentWidth == contentWidth else { return nil }
        guard cache.tabSize == editor.tabSize else { return nil }
        guard cache.lineCount == editor.lineCount else { return nil }
        guard cache.lineWrapCounts.count == editor.lineCount else { return nil }
        guard cache.visualOffsets.count == editor.lineCount else { return nil }
        return cache
    }
}
