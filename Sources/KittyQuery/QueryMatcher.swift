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
    public static func execute(query: Query, tree: SyntaxTree, byteRange: Range<Int>) -> [QueryMatch] {
        var matches: [QueryMatch] = []
        matchInNode(tree.root, query: query, source: tree.source, byteRange: byteRange, matches: &matches)
        return matches
    }

    // MARK: - Private

    private static func matchInNode(
        _ node: SyntaxNode,
        query: Query,
        source: String,
        byteRange: Range<Int>? = nil,
        matches: inout [QueryMatch]
    ) {
        // Check if node is in range
        if let range = byteRange {
            guard node.byteRange.overlaps(range) else { return }
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
            matchInNode(child, query: query, source: source, byteRange: byteRange, matches: &matches)
        }
    }

    private static func matchPattern(
        _ pattern: QueryPattern,
        against node: SyntaxNode,
        source: String,
        captures: inout [(node: SyntaxNode, name: String)]
    ) -> Bool {
        switch pattern {
        case .nodeMatch(let type, let children, let capture):
            guard node.type == type else { return false }
            // Match children patterns
            for childPattern in children {
                switch childPattern {
                case .fieldMatch(let name, let fieldPattern):
                    guard let fieldNode = node.child(forField: name) else { return false }
                    if !matchPattern(fieldPattern, against: fieldNode, source: source, captures: &captures) {
                        return false
                    }
                case .negatedField(let name):
                    if node.fields[name] != nil { return false }
                case .predicate(let pred):
                    if !evaluatePredicate(pred, captures: captures, source: source) {
                        return false
                    }
                default:
                    // Match against child nodes positionally
                    var matched = false
                    for child in node.children {
                        if matchPattern(childPattern, against: child, source: source, captures: &captures) {
                            matched = true
                            break
                        }
                    }
                    if !matched { return false }
                }
            }
            if let captureName = capture {
                captures.append((node: node, name: captureName))
            }
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
            return matchPattern(fieldPattern, against: fieldNode, source: source, captures: &captures)

        case .negatedField(let name):
            return node.fields[name] == nil

        case .predicate(let pred):
            return evaluatePredicate(pred, captures: captures, source: source)

        case .sequence(let patterns):
            for p in patterns {
                if !matchPattern(p, against: node, source: source, captures: &captures) {
                    return false
                }
            }
            return true

        case .anchor:
            return !node.isNamed
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
