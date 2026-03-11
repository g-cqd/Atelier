/// A position in a text buffer identified by line and column.
public struct TextPosition: Sendable, Equatable, Comparable {
    public var row: Int
    public var col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.col < rhs.col
    }
}

/// A text selection defined by an anchor (where the selection started)
/// and a head (where it currently ends).
///
/// The anchor may be before or after the head depending on the direction
/// of selection. Use `ordered` to obtain start/end regardless of direction.
public struct TextSelection: Sendable, Equatable {
    public var anchor: TextPosition
    public var head: TextPosition

    public init(anchor: TextPosition, head: TextPosition) {
        self.anchor = anchor
        self.head = head
    }

    /// `true` when the selection covers no characters (cursor, not a range).
    public var isCollapsed: Bool { anchor == head }

    /// Returns `(start, end)` with the earlier position first,
    /// regardless of selection direction.
    public var ordered: (start: TextPosition, end: TextPosition) {
        anchor <= head ? (anchor, head) : (head, anchor)
    }
}

extension TextSelection {
    public func extractText(from lines: (Int) -> String, lineCount: Int) -> String {
        let (start, end) = ordered
        var result = ""

        if start.row == end.row {
            let line = lines(start.row)
            let endIndex = min(end.col, line.count)
            let startIndex = min(start.col, line.count)
            let lineIndex = line.index(line.startIndex, offsetBy: startIndex)
            let endIndexStr = line.index(line.startIndex, offsetBy: endIndex)
            result = String(line[lineIndex..<endIndexStr])
        } else {
            let firstLine = lines(start.row)
            let startIndex = min(start.col, firstLine.count)
            let firstLineIndex = firstLine.index(firstLine.startIndex, offsetBy: startIndex)
            result += String(firstLine[firstLineIndex...])

            for row in (start.row + 1)..<end.row {
                result += "\n" + lines(row)
            }

            if end.row > start.row {
                let lastLine = lines(end.row)
                let endIndex = min(end.col, lastLine.count)
                let lastLineIndex = lastLine.index(lastLine.startIndex, offsetBy: endIndex)
                result += "\n" + String(lastLine[..<lastLineIndex])
            }
        }

        return result
    }
}
