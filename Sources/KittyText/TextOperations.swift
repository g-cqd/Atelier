/// Stateless editing operations that mutate a buffer and update a cursor.
public enum TextOperations {
    /// Inserts a string at the current cursor position, advancing the column.
    ///
    /// The insert is clamped to the valid range of the current line so that
    /// an out-of-bounds `cursor.col` never causes a crash.
    public static func insert(_ text: String, into buffer: inout TextBuffer, at cursor: inout TextCursor) {
        if buffer.lines.isEmpty { buffer.lines = [""] }
        var line = buffer.lines[cursor.row]
        let safeOffset = min(cursor.col, line.count)
        let index = line.index(line.startIndex, offsetBy: safeOffset)
        line.insert(contentsOf: text, at: index)
        buffer.lines[cursor.row] = line
        cursor.col += text.count
    }

    /// Splits the current line at the cursor, inserting a new line below.
    ///
    /// Text to the right of the cursor moves to the new line.
    /// The cursor moves to column 0 of the new line.
    public static func insertNewline(into buffer: inout TextBuffer, at cursor: inout TextCursor) {
        guard !buffer.lines.isEmpty else {
            buffer.lines = [""]
            cursor.row = 0
            cursor.col = 0
            return
        }
        let currentLine = buffer.lines[cursor.row]
        let prefix = String(currentLine.prefix(cursor.col))
        let suffix = String(currentLine.dropFirst(cursor.col))
        buffer.lines[cursor.row] = prefix
        buffer.lines.insert(suffix, at: cursor.row + 1)
        cursor.row += 1
        cursor.col = 0
    }

    /// Deletes the character immediately before the cursor.
    ///
    /// When the cursor is at column 0 and not on the first line, the current
    /// line is merged into the previous line.
    public static func deleteBackward(in buffer: inout TextBuffer, at cursor: inout TextCursor) {
        if cursor.col > 0 {
            var line = buffer.lines[cursor.row]
            let index = line.index(line.startIndex, offsetBy: cursor.col - 1)
            line.remove(at: index)
            buffer.lines[cursor.row] = line
            cursor.col -= 1
        } else if cursor.row > 0 {
            let removedLine = buffer.lines.remove(at: cursor.row)
            cursor.row -= 1
            cursor.col = buffer.lines[cursor.row].count
            buffer.lines[cursor.row] += removedLine
        }
    }
}
