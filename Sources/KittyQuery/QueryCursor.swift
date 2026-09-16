public import KittyParser

/// Stateful iterator for query matches within a byte/point range.
public struct QueryCursor: Sendable {
    private let query: Query
    private let tree: SyntaxTree
    private var matches: [QueryMatch]
    private var currentIndex: Int

    public init(query: Query, tree: SyntaxTree, byteRange: Range<Int>? = nil) {
        self.query = query
        self.tree = tree
        self.currentIndex = 0

        if let range = byteRange {
            self.matches = QueryMatcher.execute(query: query, tree: tree, byteRange: range)
        } else {
            self.matches = QueryMatcher.execute(query: query, tree: tree)
        }
    }

    /// Initialize with a point range filter (row/column).
    public init(query: Query, tree: SyntaxTree, pointRange: Range<Point>) {
        self.query = query
        self.tree = tree
        self.currentIndex = 0
        self.matches = QueryMatcher.execute(query: query, tree: tree, pointRange: pointRange)
    }

    /// Returns the next match, or nil if exhausted.
    public mutating func next() -> QueryMatch? {
        guard currentIndex < matches.count else { return nil }
        let match = matches[currentIndex]
        currentIndex += 1
        return match
    }

    /// Reset the cursor to iterate from the beginning.
    public mutating func reset() {
        currentIndex = 0
    }

    /// Number of remaining matches.
    public var remainingCount: Int {
        max(0, matches.count - currentIndex)
    }

    /// All matches as an array.
    public var allMatches: [QueryMatch] { matches }
}
