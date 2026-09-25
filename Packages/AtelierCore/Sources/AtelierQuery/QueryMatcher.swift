public import AtelierParser

/// Walks a syntax tree and matches query patterns, returning captures.
///
/// Every `execute` returns matches in pre-order: a node's matches come before its descendants', siblings left to right,
/// and a node's patterns in query order. At each node it tries only the patterns whose root can match the node's type
/// (``Query/candidatePatterns(forType:)``). The walk keeps its path on the heap, so any depth of tree is safe; only a
/// pattern's own nesting, which ``QueryParser`` bounds, reaches the call stack.
public enum QueryMatcher: Sendable {
    /// Execute a query against a syntax tree and return all matches.
    ///
    /// - Complexity: O(n × c) pattern attempts for n nodes and c patterns that can match a node's type, and O(depth)
    ///   memory besides the matches.
    public static func execute(query: Query, tree: SyntaxTree) -> [QueryMatch] {
        collectMatches(of: query, in: tree, byteRange: nil, pointRange: nil)
    }

    /// Execute a query within a byte range; a node that does not overlap it is skipped with its descendants.
    ///
    /// - Complexity: O(n × c) pattern attempts for the n nodes visited and c patterns that can match a node's type.
    public static func execute(query: Query, tree: SyntaxTree, byteRange range: Range<Int>)
        -> [QueryMatch]
    {
        collectMatches(of: query, in: tree, byteRange: range, pointRange: nil)
    }

    /// Execute a query within a point range (row/column); a node that does not overlap it is skipped with its
    /// descendants.
    ///
    /// - Complexity: O(n × c) pattern attempts for the n nodes visited and c patterns that can match a node's type.
    public static func execute(query: Query, tree: SyntaxTree, pointRange range: Range<Point>)
        -> [QueryMatch]
    {
        collectMatches(of: query, in: tree, byteRange: nil, pointRange: range)
    }

    /// Every pattern tried at every node, whatever its type: what `execute(query:tree:)` returned before the patterns
    /// were indexed by type, kept as the reference its tests compare with.
    static func executeTryingEveryPattern(query: Query, tree: SyntaxTree) -> [QueryMatch] {
        collectMatches(of: query, in: tree, byteRange: nil, pointRange: nil, indexed: false)
    }

    // MARK: - Private

    private static func collectMatches(
        of query: Query,
        in tree: SyntaxTree,
        byteRange: Range<Int>?,
        pointRange: Range<Point>?,
        indexed: Bool = true
    ) -> [QueryMatch] {
        // A literal pattern reads the node's bytes in place: one contiguous view of the source for the whole walk.
        var source = tree.source
        source.makeContiguousUTF8()
        let bytes = source.utf8Span.span
        let everyPattern = Array(query.patterns.indices)
        var matches: [QueryMatch] = []
        // One entry per level of the current path: that level's siblings and the next one to visit.
        var levels: [(siblings: [SyntaxNode], next: Int)] = [([tree.root], 0)]
        while let top = levels.indices.last {
            let index = levels[top].next
            guard index < levels[top].siblings.count else {
                levels.removeLast()
                continue
            }
            levels[top].next = index + 1
            let node = levels[top].siblings[index]
            if let byteRange, !node.byteRange.overlaps(byteRange) { continue }
            if let pointRange, !node.pointRange.overlaps(pointRange) { continue }
            for patternIndex in indexed ? query.candidatePatterns(forType: node.type) : everyPattern {
                var captures: [QueryMatch.Capture] = []
                if matchPattern(
                    query.patterns[patternIndex], against: node, source: source, bytes: bytes, captures: &captures)
                {
                    matches.append(QueryMatch(patternIndex: patternIndex, captures: captures))
                }
            }
            if !node.children.isEmpty {
                levels.append((node.children, 0))
            }
        }
        return matches
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func matchPattern(
        _ pattern: QueryPattern,
        against node: SyntaxNode,
        source: String,
        bytes: Span<UInt8>,
        captures: inout [QueryMatch.Capture]
    ) -> Bool {
        switch pattern {
            case .nodeMatch(let type, let children, let capture):
                if type == QueryPattern.namedWildcardType {
                    guard node.isNamed else { return false }
                } else {
                    guard node.type == type else { return false }
                }
                var localCaptures = captures
                var childCursor = 0
                for childPattern in children {
                    switch childPattern {
                        case .fieldMatch(let name, let fieldPattern):
                            guard let fieldNode = node.child(forField: name) else { return false }
                            var fieldCaptures = localCaptures
                            if !matchPattern(
                                fieldPattern, against: fieldNode, source: source, bytes: bytes, captures: &fieldCaptures
                            ) {
                                return false
                            }
                            localCaptures = fieldCaptures
                        case .negatedField(let name):
                            if node.fields[name] != nil { return false }
                        case .predicate(let pred):
                            if !evaluatePredicate(pred, captures: localCaptures, source: source) {
                                return false
                            }
                        default:
                            if case .quantified(let inner, let quantifier) = childPattern {
                                var matchCount = 0
                                while childCursor < node.children.count {
                                    var candidateCaptures = localCaptures
                                    guard
                                        matchPattern(
                                            inner,
                                            against: node.children[childCursor],
                                            source: source,
                                            bytes: bytes,
                                            captures: &candidateCaptures
                                        )
                                    else {
                                        break
                                    }
                                    childCursor += 1
                                    localCaptures = candidateCaptures
                                    matchCount += 1
                                }
                                switch quantifier {
                                    case .oneOrMore:
                                        if matchCount == 0 { return false }
                                    case .zeroOrMore:
                                        break  // always OK
                                    case .optional:
                                        break  // 0 or 1 match is fine; we stop after first non-match
                                }
                            } else {
                                var matched = false
                                while childCursor < node.children.count {
                                    var candidateCaptures = localCaptures
                                    if matchPattern(
                                        childPattern,
                                        against: node.children[childCursor],
                                        source: source,
                                        bytes: bytes,
                                        captures: &candidateCaptures
                                    ) {
                                        childCursor += 1
                                        localCaptures = candidateCaptures
                                        matched = true
                                        break
                                    }
                                    childCursor += 1
                                }
                                if !matched { return false }
                            }
                    }
                }
                if let capture {
                    localCaptures.append(QueryMatch.Capture(node: node, name: capture.name, index: capture.index))
                }
                captures = localCaptures
                return true

            case .literal(let value, let capture):
                // A quoted pattern names an anonymous node, as in tree-sitter; a named node that reads the same, such
                // as a JSON string's content `:`, or a node built over one, is not it.
                guard !node.isNamed, Self.bytes(of: node, in: bytes, equal: value) else { return false }
                if let capture {
                    captures.append(QueryMatch.Capture(node: node, name: capture.name, index: capture.index))
                }
                return true

            case .wildcard(let capture):
                if let capture {
                    captures.append(QueryMatch.Capture(node: node, name: capture.name, index: capture.index))
                }
                return true

            case .alternation(let alternatives):
                for alt in alternatives {
                    var altCaptures: [QueryMatch.Capture] = []
                    if matchPattern(alt, against: node, source: source, bytes: bytes, captures: &altCaptures) {
                        captures.append(contentsOf: altCaptures)
                        return true
                    }
                }
                return false

            case .fieldMatch(let name, let fieldPattern):
                guard let fieldNode = node.child(forField: name) else { return false }
                return matchPattern(
                    fieldPattern, against: fieldNode, source: source, bytes: bytes, captures: &captures)

            case .negatedField(let name):
                return node.fields[name] == nil

            case .predicate(let pred):
                return evaluatePredicate(pred, captures: captures, source: source)

            case .sequence(let patterns):
                var localCaptures = captures
                for p in patterns
                where !matchPattern(p, against: node, source: source, bytes: bytes, captures: &localCaptures) {
                    return false
                }
                captures = localCaptures
                return true

            case .quantified(let inner, let quantifier):
                // Quantified patterns are only meaningful as children of nodeMatch.
                // At the top level, match the inner pattern according to quantifier rules.
                switch quantifier {
                    case .optional, .zeroOrMore:
                        // Zero matches is acceptable — try matching but don't fail
                        var tryCaptures = captures
                        _ = matchPattern(inner, against: node, source: source, bytes: bytes, captures: &tryCaptures)
                        captures = tryCaptures
                        return true
                    case .oneOrMore:
                        // Must match at least once
                        return matchPattern(inner, against: node, source: source, bytes: bytes, captures: &captures)
                }

            case .anchor:
                return true
        }
    }

    /// Whether `node`'s bytes in the source are `value`'s UTF-8, compared in place, byte for byte, as tree-sitter
    /// compares a token's text: no string is built for the node, and a node that reaches outside the source matches
    /// nothing.
    /// - Complexity: O(1) when the lengths differ; O(`value`'s UTF-8 length) otherwise.
    private static func bytes(of node: SyntaxNode, in source: Span<UInt8>, equal value: String) -> Bool {
        let range = node.byteRange
        guard range.lowerBound >= 0, range.upperBound <= source.count, range.count == value.utf8.count else {
            return false
        }
        var offset = range.lowerBound
        for byte in value.utf8 {
            guard source[offset] == byte else { return false }
            offset += 1
        }
        return true
    }

    private static func evaluatePredicate(
        _ predicate: Predicate,
        captures: [QueryMatch.Capture],
        source: String
    ) -> Bool {
        Predicates.evaluate(predicate, captures: captures, source: source)
    }
}
