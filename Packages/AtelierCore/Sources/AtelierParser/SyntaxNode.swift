import Foundation

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
        byteRange: Range<Int> = 0 ..< 0,
        pointRange: Range<Point> = Point.zero ..< Point.zero,
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
        if let text = source.utf8.withContiguousStorageIfAvailable({ utf8 in
            text(from: utf8)
        }) {
            return text
        }

        let utf8 = Array(source.utf8)
        return utf8.withUnsafeBufferPointer { utf8 in
            text(from: utf8)
        }
    }

    /// Named children only.
    public var namedChildren: [SyntaxNode] {
        children.filter(\.isNamed)
    }

    /// First child with the given field name.
    public func child(forField name: String) -> SyntaxNode? {
        fields[name]?.first
    }

    private func text(from utf8: UnsafeBufferPointer<UInt8>) -> String {
        let lower = min(max(byteRange.lowerBound, 0), utf8.count)
        let upper = min(max(byteRange.upperBound, 0), utf8.count)
        guard lower < upper else { return "" }
        let buf = UnsafeBufferPointer(rebasing: utf8[lower ..< upper])
        return String(bytes: buf, encoding: .utf8) ?? String(decoding: buf, as: UTF8.self)
    }
}

// MARK: - Parse Error

public enum ParseError: Error, Sendable, Equatable {
    case invalidInput
    case noParseTable
    case parsingFailed(String)
}
