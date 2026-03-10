// MARK: - Point

public struct Point: Sendable, Equatable, Hashable, Comparable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static let zero = Point(row: 0, column: 0)

    public static func < (lhs: Point, rhs: Point) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.column < rhs.column
    }
}

// MARK: - Syntax Node

public struct SyntaxNode: Sendable, Equatable {
    public var type: String
    public var children: [SyntaxNode]
    public var byteRange: Range<Int>
    public var pointRange: Range<Point>
    public var fields: [String: [SyntaxNode]]
    public var isError: Bool
    public var isExtra: Bool
    public var isNamed: Bool

    public init(
        type: String,
        children: [SyntaxNode] = [],
        byteRange: Range<Int> = 0..<0,
        pointRange: Range<Point> = Point.zero..<Point.zero,
        fields: [String: [SyntaxNode]] = [:],
        isError: Bool = false,
        isExtra: Bool = false,
        isNamed: Bool = true
    ) {
        self.type = type
        self.children = children
        self.byteRange = byteRange
        self.pointRange = pointRange
        self.fields = fields
        self.isError = isError
        self.isExtra = isExtra
        self.isNamed = isNamed
    }

    /// The text content at this node (requires source).
    public func text(from source: String) -> String {
        let startIdx = source.utf8.index(source.utf8.startIndex, offsetBy: byteRange.lowerBound)
        let endIdx = source.utf8.index(source.utf8.startIndex, offsetBy: min(byteRange.upperBound, source.utf8.count))
        return String(source.utf8[startIdx..<endIdx]) ?? ""
    }

    /// Named children only.
    public var namedChildren: [SyntaxNode] {
        children.filter(\.isNamed)
    }

    /// First child with the given field name.
    public func child(forField name: String) -> SyntaxNode? {
        fields[name]?.first
    }
}

// MARK: - Parse Error

public enum ParseError: Error, Sendable, Equatable {
    case invalidInput
    case noParseTable
    case parsingFailed(String)
}
