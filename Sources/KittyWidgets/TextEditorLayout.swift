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
        max(0, rect.width - gutterWidth(for: editor))
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

    private static func wrappedRowCount(for line: String, contentWidth: Int) -> Int {
        guard contentWidth > 0 else { return 1 }
        let lineWidth = max(1, UnicodeWidth.displayWidth(of: line))
        return max(1, (lineWidth + contentWidth - 1) / contentWidth)
    }
}
