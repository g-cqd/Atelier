/// Cursor position and scroll state within a text buffer.
public struct TextCursor: Sendable, Equatable {
    /// Zero-based line index.
    public var row: Int
    /// Zero-based column index (in characters, not display columns).
    public var col: Int
    /// Vertical scroll offset (first visible line index).
    public var scrollRow: Int
    /// Horizontal scroll offset (first visible column index).
    public var scrollCol: Int

    public init(row: Int = 0, col: Int = 0, scrollRow: Int = 0, scrollCol: Int = 0) {
        self.row = row
        self.col = col
        self.scrollRow = scrollRow
        self.scrollCol = scrollCol
    }

    /// Clamps the cursor position to valid bounds within the given buffer.
    ///
    /// After mutation operations that may leave the cursor out of range,
    /// call this to restore a valid position.
    public mutating func clamp(to buffer: TextBuffer) {
        row = max(0, min(row, buffer.lineCount - 1))
        let lineLen = buffer.line(at: row).count
        col = max(0, min(col, lineLen))
    }
}
