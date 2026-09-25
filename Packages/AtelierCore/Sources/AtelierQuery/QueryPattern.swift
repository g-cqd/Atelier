public import AtelierParser

// MARK: - Query

/// A compiled query consisting of patterns and predicates.
///
/// Building a query numbers its captures: ``captureNames`` lists each name once, in the order the query's text first
/// names it, and every capture in ``patterns`` carries its name's index there, as each capture of a match does. A
/// caller resolves what it needs per capture name once per query, such as a highlight role, and reads it by index.
///
/// It also indexes its patterns by the node types their roots can match, so a matcher tries at each node only the
/// patterns that can match it.
public struct Query: Sendable, Equatable {
    public let patterns: [QueryPattern]
    /// Every capture name the patterns use, each once, in the order the query's text first names it.
    public let captureNames: [String]
    /// For each node type some pattern's root names, the patterns that can match a node of that type, in query order:
    /// those whose root names it, and those whose root can match any type.
    private let candidatesByType: [String: [Int]]
    /// The patterns whose root can match a node of any type, in query order: all that can match any other type.
    private let untypedCandidates: [Int]

    public init(patterns: [QueryPattern] = []) {
        var numbering = CaptureNumbering()
        self.patterns = patterns.map { numbering.number($0) }
        captureNames = numbering.names
        var byType: [String: [Int]] = [:]
        var untyped: [Int] = []
        for (index, pattern) in patterns.enumerated() {
            if let types = Self.rootTypes(of: pattern) {
                for type in types { byType[type, default: []].append(index) }
            } else {
                untyped.append(index)
            }
        }
        candidatesByType = byType.mapValues { ($0 + untyped).sorted() }
        untypedCandidates = untyped
    }

    /// The indices of the patterns that can match a node of type `type`, in query order.
    /// - Complexity: O(1) on average: one lookup of `type`.
    func candidatePatterns(forType type: String) -> [Int] {
        candidatesByType[type] ?? untypedCandidates
    }

    /// The node types `pattern` can match at its root, or nil when it can match a node of any type.
    ///
    /// A node match names its type. A sequence matches each part against the same node, so any part that names types
    /// bounds them. An alternation matches one of its alternatives, so it can match the types they name together, or
    /// any type if one of them can. A literal matches an anonymous node by its text, whatever its type.
    static func rootTypes(of pattern: QueryPattern) -> Set<String>? {
        switch pattern {
            case .nodeMatch(let type, _, _):
                return [type]
            case .sequence(let parts):
                for part in parts {
                    if let types = rootTypes(of: part) { return types }
                }
                return nil
            case .alternation(let alternatives):
                var types: Set<String> = []
                for alternative in alternatives {
                    guard let alternativeTypes = rootTypes(of: alternative) else { return nil }
                    types.formUnion(alternativeTypes)
                }
                return types
            case .quantified(let inner, .oneOrMore):
                return rootTypes(of: inner)
            case .quantified, .literal, .wildcard, .fieldMatch, .negatedField, .predicate, .anchor:
                return nil
        }
    }

    public static func == (lhs: Query, rhs: Query) -> Bool {
        lhs.patterns == rhs.patterns
    }
}

/// Gives each capture name its index in order of first use, and rewrites patterns to carry it.
private struct CaptureNumbering {
    var names: [String] = []
    var indices: [String: Int] = [:]

    mutating func number(_ capture: QueryPattern.Capture?) -> QueryPattern.Capture? {
        guard let capture else { return nil }
        if let index = indices[capture.name] {
            return QueryPattern.Capture(capture.name, index: index)
        }
        indices[capture.name] = names.count
        names.append(capture.name)
        return QueryPattern.Capture(capture.name, index: names.count - 1)
    }

    /// Children before the node's own capture, which the text writes after them: `(pair (key) @key) @pair`.
    mutating func number(_ pattern: QueryPattern) -> QueryPattern {
        switch pattern {
            case .nodeMatch(let type, let children, let capture):
                let numberedChildren = children.map { number($0) }
                return .nodeMatch(type: type, children: numberedChildren, capture: number(capture))
            case .fieldMatch(let name, let inner):
                return .fieldMatch(name: name, pattern: number(inner))
            case .literal(let value, let capture):
                return .literal(value, capture: number(capture))
            case .wildcard(let capture):
                return .wildcard(capture: number(capture))
            case .alternation(let alternatives):
                return .alternation(alternatives.map { number($0) })
            case .sequence(let patterns):
                return .sequence(patterns.map { number($0) })
            case .quantified(let inner, let quantifier):
                return .quantified(pattern: number(inner), quantifier: quantifier)
            case .negatedField, .predicate, .anchor:
                return pattern
        }
    }
}

// MARK: - Quantifier

/// Repetition semantics for a quantified pattern.
public enum Quantifier: Sendable, Equatable {
    case oneOrMore
    case zeroOrMore
    case optional
}

// MARK: - Query Pattern

/// A single pattern in a query, matching against syntax tree nodes.
public indirect enum QueryPattern: Sendable, Equatable {
    case nodeMatch(type: String, children: [QueryPattern], capture: Capture?)
    case fieldMatch(name: String, pattern: QueryPattern)
    case literal(String, capture: Capture?)
    case wildcard(capture: Capture?)
    case alternation([QueryPattern])
    case negatedField(String)
    case predicate(Predicate)
    case sequence([QueryPattern])
    case anchor  // for `.` (anonymous nodes)
    case quantified(pattern: QueryPattern, quantifier: Quantifier)
}

extension QueryPattern {
    /// A capture in a pattern: its name, and its index in the ``Query/captureNames`` of the query that holds the
    /// pattern. A string literal is a capture of that name; the query numbers it.
    public struct Capture: Sendable, Hashable, ExpressibleByStringLiteral {
        public let name: String
        /// The index of ``name`` in the holding query's ``Query/captureNames``, or -1 in a pattern no query holds.
        public let index: Int

        public init(_ name: String, index: Int = -1) {
            self.name = name
            self.index = index
        }

        public init(stringLiteral name: String) {
            self.init(name)
        }

        /// Equal by name: within a query the index follows from the name.
        public static func == (lhs: Capture, rhs: Capture) -> Bool {
            lhs.name == rhs.name
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }
}

// MARK: - Predicate

public enum Predicate: Sendable, Equatable {
    case eq(capture: String, value: String)
    case notEq(capture: String, value: String)
    case match(capture: String, pattern: String)
    case notMatch(capture: String, pattern: String)
    case anyOf(capture: String, values: [String])
    case contains(capture: String, value: String)
    /// `(#is? [@capture] property [value])`: the capture, or the match when none is named, has `property`. As in
    /// tree-sitter, the capture may stand anywhere among the arguments and the value is optional.
    case `is`(capture: String?, property: String, value: String?)
    /// `(#is-not? [@capture] property [value])`: the negation of ``is(capture:property:value:)``.
    case isNot(capture: String?, property: String, value: String?)
    case directive(name: String, arguments: [String])
}

// MARK: - Query Match

/// A match result from running a query against a syntax tree.
public struct QueryMatch: Sendable, Equatable {
    /// A node a match captured, with the capture's name and that name's index in the query's ``Query/captureNames``.
    public struct Capture: Sendable, Equatable {
        public var node: SyntaxNode
        public var name: String
        public var index: Int

        public init(node: SyntaxNode, name: String, index: Int) {
            self.node = node
            self.name = name
            self.index = index
        }
    }

    public var patternIndex: Int
    public var captures: [Capture]

    public init(patternIndex: Int, captures: [Capture]) {
        self.patternIndex = patternIndex
        self.captures = captures
    }
}

// MARK: - Query Error

public enum QueryError: Error, Sendable, Equatable {
    case syntaxError(String)
    case unknownPredicate(String)
    case invalidCapture(String)
}
