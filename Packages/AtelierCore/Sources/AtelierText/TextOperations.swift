/// Stateless editing operations that mutate a buffer and update a cursor.
public enum TextOperations {
    /// Inserts a string at the current cursor position, advancing the column.
    ///
    /// The insert is clamped to the valid range of the current line so that
    /// an out-of-bounds `cursor.col` never causes a crash.
    @discardableResult
    public static func insert(
        _ text: String, into buffer: inout TextBuffer, at cursor: inout TextCursor
    ) -> TextMutation {
        if buffer.lineCount == 0 { buffer.lines = [""] }
        let row = cursor.row
        let line = buffer.line(at: row)
        let safeOffset = min(cursor.col, line.count)
        let index = line.index(line.startIndex, offsetBy: safeOffset)

        guard text.contains("\n") else {
            var updatedLine = line
            updatedLine.insert(contentsOf: text, at: index)
            buffer.setLine(at: row, to: updatedLine)
            cursor.col = safeOffset + text.count
            return TextMutation(
                originalLineRange: row ..< (row + 1),
                updatedLineRange: row ..< (row + 1)
            )
        }

        let insertedLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(
                String.init)
        let prefix = String(line[..<index])
        let suffix = String(line[index...])

        buffer.setLine(at: row, to: prefix + insertedLines[0])

        for (offset, insertedLine) in insertedLines.enumerated().dropFirst() {
            let newLine = offset == insertedLines.count - 1 ? insertedLine + suffix : insertedLine
            buffer.insertLine(newLine, at: row + offset)
        }

        cursor.row = row + insertedLines.count - 1
        cursor.col = insertedLines.last?.count ?? 0
        return TextMutation(
            originalLineRange: row ..< (row + 1),
            updatedLineRange: row ..< (row + insertedLines.count)
        )
    }

    /// Splits the current line at the cursor, inserting a new line below.
    ///
    /// Text to the right of the cursor moves to the new line.
    /// The cursor moves to column 0 of the new line.
    @discardableResult
    public static func insertNewline(into buffer: inout TextBuffer, at cursor: inout TextCursor)
        -> TextMutation
    {
        insert("\n", into: &buffer, at: &cursor)
    }

    /// Deletes the character immediately before the cursor.
    ///
    /// When cursor is at column 0 and not on the first line, the current
    /// line is merged into the previous line.
    @discardableResult
    public static func deleteBackward(in buffer: inout TextBuffer, at cursor: inout TextCursor)
        -> TextMutation?
    {
        if cursor.col > 0 {
            var line = buffer.line(at: cursor.row)
            let index = line.index(line.startIndex, offsetBy: cursor.col - 1)
            line.remove(at: index)
            buffer.setLine(at: cursor.row, to: line)
            cursor.col -= 1
            return TextMutation(
                originalLineRange: cursor.row ..< (cursor.row + 1),
                updatedLineRange: cursor.row ..< (cursor.row + 1)
            )
        } else if cursor.row > 0 {
            let mergedRow = cursor.row - 1
            let removedLine = buffer.removeLine(at: cursor.row)
            cursor.row -= 1
            cursor.col = buffer.line(at: cursor.row).count
            buffer.setLine(at: cursor.row, to: buffer.line(at: cursor.row) + removedLine)
            return TextMutation(
                originalLineRange: mergedRow ..< (mergedRow + 2),
                updatedLineRange: mergedRow ..< (mergedRow + 1)
            )
        }

        return nil
    }

    /// Deletes the line at the current cursor row.
    ///
    /// When the buffer has more than one line, the entire line including its newline is removed
    /// and the cursor is placed at column 0 of the next line (or the last line if at the end).
    /// When the buffer has only one line, the line content is cleared but the line itself is kept.
    @discardableResult
    public static func deleteLine(in buffer: inout TextBuffer, at cursor: inout TextCursor)
        -> TextMutation
    {
        let lineIndex = cursor.row
        let lineCount = buffer.lineCount

        if lineCount <= 1 {
            buffer.setLine(at: lineIndex, to: "")
            cursor.col = 0
            return TextMutation(
                originalLineRange: lineIndex ..< (lineIndex + 1),
                updatedLineRange: lineIndex ..< (lineIndex + 1)
            )
        }

        buffer.removeLine(at: lineIndex)
        cursor.row = min(lineIndex, buffer.lineCount - 1)
        cursor.col = 0
        return TextMutation(
            originalLineRange: lineIndex ..< (lineIndex + 1),
            updatedLineRange: lineIndex ..< lineIndex
        )
    }

    @discardableResult
    public static func deleteRange(
        in buffer: inout TextBuffer, at cursor: inout TextCursor, selection: TextSelection
    ) -> TextMutation {
        let (start, end) = selection.ordered

        guard start.row == end.row else {
            let firstLine = buffer.line(at: start.row)
            let firstStartIndex = firstLine.index(
                firstLine.startIndex, offsetBy: min(start.col, firstLine.count))
            let firstPrefix = String(firstLine[..<firstStartIndex])

            let lastLine = buffer.line(at: end.row)
            let lastEndIndex = lastLine.index(
                lastLine.startIndex, offsetBy: min(end.col, lastLine.count))
            let lastSuffix = String(lastLine[lastEndIndex...])

            buffer.setLine(at: start.row, to: firstPrefix + lastSuffix)

            for _ in (start.row + 1) ... end.row {
                buffer.removeLine(at: start.row + 1)
            }

            cursor.row = start.row
            cursor.col = start.col
            return TextMutation(
                originalLineRange: start.row ..< (end.row + 1),
                updatedLineRange: start.row ..< (start.row + 1)
            )
        }
        var line = buffer.line(at: start.row)
        let startIndex = line.index(line.startIndex, offsetBy: min(start.col, line.count))
        let endIndex = line.index(line.startIndex, offsetBy: min(end.col, line.count))
        line.removeSubrange(startIndex ..< endIndex)
        buffer.setLine(at: start.row, to: line)
        cursor.row = start.row
        cursor.col = start.col
        return TextMutation(
            originalLineRange: start.row ..< (start.row + 1),
            updatedLineRange: start.row ..< (start.row + 1)
        )
    }
}
