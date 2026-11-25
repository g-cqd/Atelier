/// Positions in a document's text, in the unit each boundary needs (text-renderer.md §3.2): UTF-8 bytes end to end,
/// UTF-16 only where AppKit or CoreText demand it, and a row index for the line-based layout.

/// A byte offset into one row's UTF-8 text.
public struct ByteOffset: Hashable, Comparable, Sendable {
    public var rawValue: Int32

    public init(_ rawValue: Int32) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = Int32(rawValue) }

    public static func < (lhs: ByteOffset, rhs: ByteOffset) -> Bool { lhs.rawValue < rhs.rawValue }
    public static func + (lhs: ByteOffset, rhs: Int) -> ByteOffset { ByteOffset(lhs.rawValue + Int32(rhs)) }
    public static func - (lhs: ByteOffset, rhs: ByteOffset) -> Int { Int(lhs.rawValue) - Int(rhs.rawValue) }
}

/// A UTF-16 offset, only at AppKit and CoreText boundaries.
public struct UTF16Offset: Hashable, Comparable, Sendable {
    public var rawValue: Int32

    public init(_ rawValue: Int32) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = Int32(rawValue) }

    public static func < (lhs: UTF16Offset, rhs: UTF16Offset) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A row in a document, from zero.
public struct RowIndex: Hashable, Comparable, Strideable, Sendable {
    public var rawValue: Int32

    public init(_ rawValue: Int32) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = Int32(rawValue) }

    public static func < (lhs: RowIndex, rhs: RowIndex) -> Bool { lhs.rawValue < rhs.rawValue }
    public func distance(to other: RowIndex) -> Int { Int(other.rawValue) - Int(rawValue) }
    public func advanced(by n: Int) -> RowIndex { RowIndex(Int(rawValue) + n) }

    /// This row as a plain `Int`, for indexing arrays.
    public var index: Int { Int(rawValue) }
}

/// A position in the document: a row and a byte offset on a scalar boundary within it.
public struct TextPosition: Hashable, Comparable, Sendable {
    public var row: RowIndex
    public var offset: ByteOffset

    public init(row: RowIndex, offset: ByteOffset) {
        self.row = row
        self.offset = offset
    }

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        lhs.row == rhs.row ? lhs.offset < rhs.offset : lhs.row < rhs.row
    }
}

/// A half-open range between two positions, possibly spanning rows.
public struct TextRange: Hashable, Sendable {
    public var lowerBound: TextPosition
    public var upperBound: TextPosition

    public init(lowerBound: TextPosition, upperBound: TextPosition) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}
