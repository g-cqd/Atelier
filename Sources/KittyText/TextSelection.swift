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
