/// Stateless navigation operations that move a cursor within a buffer.
public enum TextNavigation {
    /// Advances the cursor past the current word and any trailing whitespace,
    /// stopping at the start of the next word (or end of line).
    public static func moveWordForward(cursor: inout TextCursor, in buffer: TextBuffer) {
        let chars = Array(buffer.line(at: cursor.row))
        guard cursor.col < chars.count else { return }
        var pos = cursor.col
        while pos < chars.count && !chars[pos].isWhitespace { pos += 1 }
        while pos < chars.count && chars[pos].isWhitespace { pos += 1 }
        cursor.col = min(pos, chars.count)
    }

    /// Moves the cursor backward to the start of the previous word.
    public static func moveWordBackward(cursor: inout TextCursor, in buffer: TextBuffer) {
        let chars = Array(buffer.line(at: cursor.row))
        guard cursor.col > 0 else { return }
        var pos = max(0, cursor.col - 1)
        while pos > 0 && chars[pos].isWhitespace { pos -= 1 }
        while pos > 0 && !chars[pos].isWhitespace { pos -= 1 }
        if pos > 0 && chars[pos].isWhitespace { pos += 1 }
        cursor.col = pos
    }

    /// Adjusts the scroll offsets so the cursor remains within the visible viewport.
    ///
    /// - Parameters:
    ///   - cursor: The cursor whose position and scroll state to update.
    ///   - visibleRows: Number of lines visible on screen.
    ///   - visibleCols: Number of columns visible on screen.
    ///   - wrapLines: When `true`, horizontal scrolling is disabled and `scrollCol` is reset to zero.
    public static func ensureVisible(
        cursor: inout TextCursor,
        visibleRows: Int,
        visibleCols: Int,
        wrapLines: Bool
    ) {
        if cursor.row < cursor.scrollRow {
            cursor.scrollRow = cursor.row
        } else if cursor.row >= cursor.scrollRow + visibleRows {
            cursor.scrollRow = max(0, cursor.row - visibleRows + 1)
        }

        if wrapLines {
            cursor.scrollCol = 0
        } else {
            if cursor.col < cursor.scrollCol {
                cursor.scrollCol = cursor.col
            } else if cursor.col >= cursor.scrollCol + visibleCols {
                cursor.scrollCol = max(0, cursor.col - visibleCols + 1)
            }
        }
    }
}
