import KittyParser

// MARK: - Query

/// A compiled query consisting of patterns and predicates.
public struct Query: Sendable, Equatable {
    public var patterns: [QueryPattern]

    public init(patterns: [QueryPattern] = []) {
        self.patterns = patterns
    }
}

// MARK: - Query Pattern

/// A single pattern in a query, matching against syntax tree nodes.
public indirect enum QueryPattern: Sendable, Equatable {
    case nodeMatch(type: String, children: [QueryPattern], capture: String?)
    case fieldMatch(name: String, pattern: QueryPattern)
    case literal(String, capture: String?)
    case wildcard(capture: String?)
    case alternation([QueryPattern])
    case negatedField(String)
    case predicate(Predicate)
    case sequence([QueryPattern])
    case anchor // for `.` (anonymous nodes)
}

// MARK: - Predicate

public enum Predicate: Sendable, Equatable {
    case eq(capture: String, value: String)
    case notEq(capture: String, value: String)
    case match(capture: String, pattern: String)
    case notMatch(capture: String, pattern: String)
    case anyOf(capture: String, values: [String])
    case contains(capture: String, value: String)
    case `is`(capture: String, property: String)
    case isNot(capture: String, property: String)
}

// MARK: - Query Match

/// A match result from running a query against a syntax tree.
public struct QueryMatch: Sendable, Equatable {
    public var patternIndex: Int
    public var captures: [(node: SyntaxNode, name: String)]

    public init(patternIndex: Int, captures: [(node: SyntaxNode, name: String)]) {
        self.patternIndex = patternIndex
        self.captures = captures
    }

    public static func == (lhs: QueryMatch, rhs: QueryMatch) -> Bool {
        lhs.patternIndex == rhs.patternIndex &&
        lhs.captures.count == rhs.captures.count &&
        zip(lhs.captures, rhs.captures).allSatisfy { $0.node == $1.node && $0.name == $1.name }
    }
}

// MARK: - Query Error

public enum QueryError: Error, Sendable, Equatable {
    case syntaxError(String)
    case unknownPredicate(String)
    case invalidCapture(String)
}
