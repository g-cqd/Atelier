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
        editor.showLineNumbers ? max(3, editor.lineNumberWidth + 1) : 0
    }

    public static func contentWidth(for editor: TextEditor, in rect: Rect) -> Int {
        max(0, rect.width - gutterWidth(for: editor) - verticalScrollIndicatorWidth(for: editor, in: rect))
    }

    public static func verticalScrollMetrics(for editor: TextEditor, in rect: Rect) -> ScrollMetrics {
        if editor.wrapLines {
            let contentWidth = max(1, contentWidth(for: editor, in: rect))
            let visualRowCount = totalWrappedRowCount(for: editor.lines, contentWidth: contentWidth)
            let visualOffset = visualRowOffset(
                forLineOffset: editor.scrollOffset,
                lines: editor.lines,
                contentWidth: contentWidth
            )
            let maxOffset = visualRowOffset(
                forLineOffset: max(0, editor.lines.count - 1),
                lines: editor.lines,
                contentWidth: contentWidth
            )
            return ScrollMetrics(
                contentLength: visualRowCount,
                viewportLength: rect.height,
                offset: visualOffset,
                maxOffset: maxOffset
            )
        }

        return ScrollMetrics(
            contentLength: editor.lines.count,
            viewportLength: rect.height,
            offset: editor.scrollOffset,
            maxOffset: max(0, editor.lines.count - 1)
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
        guard let indicatorRect = verticalScrollIndicatorRect(for: editor, in: rect) else { return nil }
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
        guard let indicatorRect = verticalScrollIndicatorRect(for: editor, in: rect) else {
            return editor.scrollOffset
        }

        let metrics = verticalScrollMetrics(for: editor, in: rect)
        let nextOffset = VerticalScrollIndicatorLayout.offset(
            for: metrics,
            in: indicatorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )

        guard editor.wrapLines else { return nextOffset }
        let wrappedContentWidth = max(1, contentWidth(for: editor, in: rect))
        return lineOffset(
            forVisualRowOffset: nextOffset,
            lines: editor.lines,
            contentWidth: wrappedContentWidth
        )
    }

    public static func cursorPosition(for editor: TextEditor, in rect: Rect) -> CursorPosition? {
        guard editor.modeShowsCursor else { return nil }
        guard rect.height > 0 else { return nil }
        guard editor.cursorRow >= 0 && editor.cursorRow < editor.lines.count else { return nil }

        let gutterWidth = gutterWidth(for: editor)
        let contentWidth = max(1, contentWidth(for: editor, in: rect))
        let startLine = max(0, min(editor.scrollOffset, editor.lines.count))
        guard editor.cursorRow >= startLine else { return nil }

        let line = editor.lines[editor.cursorRow]
        let displayColumn = TextDisplayMetrics.displayColumn(forCharacterOffset: editor.cursorCol, in: line)

        if editor.wrapLines {
            var screenRow = 0
            for lineIndex in startLine..<editor.cursorRow {
                screenRow += wrappedRowCount(for: editor.lines[lineIndex], contentWidth: contentWidth)
                if screenRow >= rect.height { return nil }
            }

            let wrapRow = displayColumn / contentWidth
            let row = screenRow + wrapRow
            guard row < rect.height else { return nil }
            return CursorPosition(
                row: rect.y + row,
                col: rect.x + gutterWidth + (displayColumn % contentWidth)
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
           col >= indicatorRect.x && col < indicatorRect.maxX {
            return nil
        }

        let gutterWidth = gutterWidth(for: editor)
        let contentWidth = max(1, contentWidth(for: editor, in: rect))
        let relativeRow = row - rect.y
        let relativeColumn = max(0, col - rect.x - gutterWidth)
        let displayColumn = min(relativeColumn, contentWidth - 1)
        let startLine = max(0, min(editor.scrollOffset, editor.lines.count))

        if editor.wrapLines {
            var screenRow = 0
            for lineIndex in startLine..<editor.lines.count {
                let wrappedRows = wrappedRowCount(for: editor.lines[lineIndex], contentWidth: contentWidth)
                let nextScreenRow = screenRow + wrappedRows
                if relativeRow < nextScreenRow {
                    let wrapRow = relativeRow - screenRow
                    let line = editor.lines[lineIndex]
                    let wrappedDisplayColumn = wrapRow * contentWidth + displayColumn
                    return TextPosition(
                        row: lineIndex,
                        col: TextDisplayMetrics.characterOffset(
                            forDisplayColumn: wrappedDisplayColumn,
                            in: line
                        )
                    )
                }
                screenRow = nextScreenRow
                if screenRow >= rect.height { break }
            }
            return nil
        }

        let lineIndex = startLine + relativeRow
        guard lineIndex >= 0 && lineIndex < editor.lines.count else { return nil }
        let line = editor.lines[lineIndex]
        return TextPosition(
            row: lineIndex,
            col: TextDisplayMetrics.characterOffset(
                forDisplayColumn: displayColumn + editor.horizontalScrollOffset,
                in: line
            )
        )
    }

    private static func verticalScrollIndicatorWidth(for editor: TextEditor, in rect: Rect) -> Int {
        editor.showsVerticalScrollIndicator && rect.width > 0 ? 1 : 0
    }

    private static func wrappedRowCount(for line: String, contentWidth: Int) -> Int {
        guard contentWidth > 0 else { return 1 }
        let lineWidth = max(1, UnicodeWidth.displayWidth(of: line))
        return max(1, (lineWidth + contentWidth - 1) / contentWidth)
    }

    private static func totalWrappedRowCount(for lines: [String], contentWidth: Int) -> Int {
        lines.reduce(into: 0) { total, line in
            total += wrappedRowCount(for: line, contentWidth: contentWidth)
        }
    }

    private static func visualRowOffset(
        forLineOffset lineOffset: Int,
        lines: [String],
        contentWidth: Int
    ) -> Int {
        guard !lines.isEmpty else { return 0 }

        let clampedLineOffset = min(max(0, lineOffset), max(0, lines.count - 1))
        var visualOffset = 0

        for lineIndex in 0..<clampedLineOffset {
            visualOffset += wrappedRowCount(for: lines[lineIndex], contentWidth: contentWidth)
        }

        return visualOffset
    }

    private static func lineOffset(
        forVisualRowOffset visualRowOffset: Int,
        lines: [String],
        contentWidth: Int
    ) -> Int {
        guard !lines.isEmpty else { return 0 }

        let resolvedVisualRowOffset = max(0, visualRowOffset)
        var currentVisualRow = 0

        for (lineIndex, line) in lines.enumerated() {
            let nextVisualRow = currentVisualRow + wrappedRowCount(for: line, contentWidth: contentWidth)
            if resolvedVisualRowOffset < nextVisualRow {
                return lineIndex
            }
            currentVisualRow = nextVisualRow
        }

        return max(0, lines.count - 1)
    }
}
