import KittyParser

/// Walks a syntax tree and matches query patterns, returning captures.
public enum QueryMatcher: Sendable {

    /// Execute a query against a syntax tree and return all matches.
    public static func execute(query: Query, tree: SyntaxTree) -> [QueryMatch] {
        var matches: [QueryMatch] = []
        matchInNode(tree.root, query: query, source: tree.source, matches: &matches)
        return matches
    }

    /// Execute a query within a byte range.
    public static func execute(query: Query, tree: SyntaxTree, byteRange range: Range<Int>)
        -> [QueryMatch]
    {
        var matches: [QueryMatch] = []
        matchInNode(
            tree.root, query: query, source: tree.source, byteRange: range, pointRange: nil,
            matches: &matches)
        return matches
    }

    /// Execute a query within a point range (row/column).
    public static func execute(query: Query, tree: SyntaxTree, pointRange range: Range<Point>)
        -> [QueryMatch]
    {
        var matches: [QueryMatch] = []
        matchInNode(
            tree.root, query: query, source: tree.source, byteRange: nil, pointRange: range,
            matches: &matches)
        return matches
    }

    // MARK: - Private

    private static func matchInNode(
        _ node: SyntaxNode,
        query: Query,
        source: String,
        byteRange: Range<Int>? = nil,
        pointRange: Range<Point>? = nil,
        matches: inout [QueryMatch]
    ) {
        // Check if node is in range
        if let range = byteRange {
            guard node.byteRange.overlaps(range) else { return }
        }
        if let range = pointRange {
            guard node.pointRange.overlaps(range) else { return }
        }

        // Try each pattern against this node
        for (patternIdx, pattern) in query.patterns.enumerated() {
            var captures: [(node: SyntaxNode, name: String)] = []
            if matchPattern(pattern, against: node, source: source, captures: &captures) {
                matches.append(QueryMatch(patternIndex: patternIdx, captures: captures))
            }
        }

        // Recurse into children
        for child in node.children {
            matchInNode(
                child, query: query, source: source, byteRange: byteRange, pointRange: pointRange,
                matches: &matches)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func matchPattern(
        _ pattern: QueryPattern,
        against node: SyntaxNode,
        source: String,
        captures: inout [(node: SyntaxNode, name: String)]
    ) -> Bool {
        switch pattern {
        case .nodeMatch(let type, let children, let capture):
            guard node.type == type else { return false }
            var localCaptures = captures
            var childCursor = 0
            for childPattern in children {
                switch childPattern {
                case .fieldMatch(let name, let fieldPattern):
                    guard let fieldNode = node.child(forField: name) else { return false }
                    var fieldCaptures = localCaptures
                    if !matchPattern(
                        fieldPattern, against: fieldNode, source: source, captures: &fieldCaptures)
                    {
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
                            if matchPattern(
                                inner,
                                against: node.children[childCursor],
                                source: source,
                                captures: &candidateCaptures
                            ) {
                                childCursor += 1
                                localCaptures = candidateCaptures
                                matchCount += 1
                            } else {
                                break
                            }
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
            if let captureName = capture {
                localCaptures.append((node: node, name: captureName))
            }
            captures = localCaptures
            return true

        case .literal(let value, let capture):
            let nodeText = node.text(from: source)
            guard nodeText == value else { return false }
            if let captureName = capture {
                captures.append((node: node, name: captureName))
            }
            return true

        case .wildcard(let capture):
            if let captureName = capture {
                captures.append((node: node, name: captureName))
            }
            return true

        case .alternation(let alternatives):
            for alt in alternatives {
                var altCaptures: [(node: SyntaxNode, name: String)] = []
                if matchPattern(alt, against: node, source: source, captures: &altCaptures) {
                    captures.append(contentsOf: altCaptures)
                    return true
                }
            }
            return false

        case .fieldMatch(let name, let fieldPattern):
            guard let fieldNode = node.child(forField: name) else { return false }
            return matchPattern(
                fieldPattern, against: fieldNode, source: source, captures: &captures)

        case .negatedField(let name):
            return node.fields[name] == nil

        case .predicate(let pred):
            return evaluatePredicate(pred, captures: captures, source: source)

        case .sequence(let patterns):
            var localCaptures = captures
            for p in patterns where !matchPattern(p, against: node, source: source, captures: &localCaptures) {
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
                _ = matchPattern(inner, against: node, source: source, captures: &tryCaptures)
                captures = tryCaptures
                return true
            case .oneOrMore:
                // Must match at least once
                return matchPattern(inner, against: node, source: source, captures: &captures)
            }

        case .anchor:
            return true
        }
    }

    private static func evaluatePredicate(
        _ predicate: Predicate,
        captures: [(node: SyntaxNode, name: String)],
        source: String
    ) -> Bool {
        Predicates.evaluate(predicate, captures: captures, source: source)
    }
}
