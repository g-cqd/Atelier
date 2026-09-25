public import AtelierParser

/// Walks a syntax tree and matches query patterns, returning captures.
///
/// Every `execute` returns matches in pre-order: a node's matches come before its descendants', siblings left to right,
/// and a node's patterns in query order. At each node it tries only the patterns whose root can match the node's type
/// (``Query/candidatePatterns(forType:)``). The walk keeps its path on the heap, so any depth of tree is safe; only a
/// pattern's own nesting, which ``QueryParser`` bounds, reaches the call stack.
///
/// As tree-sitter's query cursor does, a pattern matches a node in every way it can: each child step may take any
/// later child than the step before it, so `(command (_) @arg)` matches once per named child. Of the ways that
/// capture the same nodes, or only some of the nodes another way captures, it keeps one, the longest, and then the
/// pattern's predicates filter what is left, as tree-sitter's bindings filter the matches its cursor returns.
public enum QueryMatcher: Sendable {
    /// Execute a query against a syntax tree and return all matches.
    ///
    /// - Complexity: O(n × c) pattern attempts for n nodes and c patterns that can match a node's type, and O(depth)
    ///   memory besides the matches. An attempt tries every way the pattern's child steps can take the node's
    ///   children: one per child for a single child step, and at worst a product over the child steps.
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
        var state = MatchState()
        var ways: [Way] = []
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
                ways.removeAll(keepingCapacity: true)
                _ = forEachWay(of: query.patterns[patternIndex], at: node, bytes: bytes, state: &state) { state in
                    ways.append(Way(captures: state.captures, predicates: state.predicates))
                    return true
                }
                if ways.count > 1 { removeShorterWays(&ways) }
                for way in ways
                where way.predicates.allSatisfy({
                    Predicates.evaluate($0, captures: way.captures, source: source)
                }) {
                    matches.append(QueryMatch(patternIndex: patternIndex, captures: way.captures))
                }
            }
            if !node.children.isEmpty {
                levels.append((node.children, 0))
            }
        }
        return matches
    }

    /// Calls `body` once for each way `pattern` matches `node`, with the way's captures and predicates pushed on
    /// `state`, which it leaves as it found it. It stops, and returns false, as soon as `body` returns false.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func forEachWay(
        of pattern: QueryPattern,
        at node: SyntaxNode,
        bytes: Span<UInt8>,
        state: inout MatchState,
        _ body: (inout MatchState) -> Bool
    ) -> Bool {
        switch pattern {
            case .nodeMatch(let type, let steps, let capture):
                if type == QueryPattern.namedWildcardType {
                    guard node.isNamed else { return true }
                } else {
                    guard node.type == type else { return true }
                }
                guard !steps.isEmpty else { return state.with(capture, of: node, body) }
                return forEachWay(ofSteps: steps[...], from: 0, limit: nil, of: node, bytes: bytes, state: &state) {
                    state in
                    state.with(capture, of: node, body)
                }

            case .literal(let value, let capture):
                // A quoted pattern names an anonymous node, as in tree-sitter; a named node that reads the same, such
                // as a JSON string's content `:`, or a node built over one, is not it.
                guard !node.isNamed, Self.bytes(of: node, in: bytes, equal: value) else { return true }
                return state.with(capture, of: node, body)

            case .wildcard(let capture):
                return state.with(capture, of: node, body)

            case .alternation(let alternatives):
                // Each alternative that matches is a way of its own, as each is a branch of tree-sitter's steps.
                for alternative in alternatives {
                    guard forEachWay(of: alternative, at: node, bytes: bytes, state: &state, body) else { return false }
                }
                return true

            case .fieldMatch(let name, let fieldPattern):
                for fieldNode in node.fields[name] ?? [] {
                    guard forEachWay(of: fieldPattern, at: fieldNode, bytes: bytes, state: &state, body) else {
                        return false
                    }
                }
                return true

            case .negatedField(let name):
                return node.fields[name] == nil ? body(&state) : true

            case .predicate(let predicate):
                state.predicates.append(predicate)
                defer { state.predicates.removeLast() }
                return body(&state)

            case .sequence(let parts):
                return forEachWay(ofParts: parts[...], at: node, bytes: bytes, state: &state, body)

            case .quantified(let inner, let quantifier):
                // Quantified patterns are only meaningful as children of nodeMatch. At the top level, `+` is its inner
                // pattern, and `?` and `*` are its inner pattern, or no capture at all where that does not match.
                if quantifier == .oneOrMore {
                    return forEachWay(of: inner, at: node, bytes: bytes, state: &state, body)
                }
                var matched = false
                let finished = forEachWay(of: inner, at: node, bytes: bytes, state: &state) { state in
                    matched = true
                    return body(&state)
                }
                guard finished else { return false }
                return matched ? true : body(&state)

            case .anchor:
                return body(&state)
        }
    }

    /// Calls `body` once for each way all of `parts` match `node`, as a sequence matches one node with each of them.
    private static func forEachWay(
        ofParts parts: ArraySlice<QueryPattern>,
        at node: SyntaxNode,
        bytes: Span<UInt8>,
        state: inout MatchState,
        _ body: (inout MatchState) -> Bool
    ) -> Bool {
        guard let first = parts.first else { return body(&state) }
        return forEachWay(of: first, at: node, bytes: bytes, state: &state) { state in
            forEachWay(ofParts: parts.dropFirst(), at: node, bytes: bytes, state: &state, body)
        }
    }

    /// Calls `body` once for each way `steps`, the child patterns of a node pattern, match `node`'s children from
    /// `cursor` on.
    ///
    /// A child step takes any child after the one the step before it took, skipping those between, as a tree-sitter
    /// step that is not anchored may match any later sibling (`later_sibling_can_match` in ts_query_cursor__advance,
    /// lib/src/query.c). Field, negated-field and predicate steps take no child.
    ///
    /// `limit`, when set, is the last child the next step that takes a child may take. A quantified step sets it when
    /// it leaves a child it could take: a way that takes a later child instead, or none, captures only some of what the
    /// way that takes it captures, and tree-sitter keeps only the longer (``removeShorterWays(_:)``). So the matcher
    /// does not make such a way, and a way that ends with a limit set is none.
    // swiftlint:disable:next function_parameter_count
    private static func forEachWay(
        ofSteps steps: ArraySlice<QueryPattern>,
        from cursor: Int,
        limit: Int?,
        of node: SyntaxNode,
        bytes: Span<UInt8>,
        state: inout MatchState,
        _ body: (inout MatchState) -> Bool
    ) -> Bool {
        guard let step = steps.first else { return limit == nil ? body(&state) : true }
        let rest = steps.dropFirst()
        switch step {
            case .fieldMatch(let name, let fieldPattern):
                for fieldNode in node.fields[name] ?? [] {
                    let finished = forEachWay(of: fieldPattern, at: fieldNode, bytes: bytes, state: &state) { state in
                        forEachWay(
                            ofSteps: rest, from: cursor, limit: limit, of: node, bytes: bytes, state: &state, body)
                    }
                    guard finished else { return false }
                }
                return true

            case .negatedField(let name):
                guard node.fields[name] == nil else { return true }
                return forEachWay(
                    ofSteps: rest, from: cursor, limit: limit, of: node, bytes: bytes, state: &state, body)

            case .predicate(let predicate):
                state.predicates.append(predicate)
                defer { state.predicates.removeLast() }
                return forEachWay(
                    ofSteps: rest, from: cursor, limit: limit, of: node, bytes: bytes, state: &state, body)

            case .anchor:
                // An anchor takes the child at the cursor, whatever it is.
                guard cursor < node.children.count else { return true }
                return forEachWay(
                    ofSteps: rest, from: cursor + 1, limit: nil, of: node, bytes: bytes, state: &state, body)

            case .quantified:
                return forEachRun(
                    ofSteps: steps, from: cursor, limit: limit, of: node, bytes: bytes, state: &state, body)

            default:
                let children = node.children
                let last = min(limit ?? children.count - 1, children.count - 1)
                guard cursor <= last else { return true }
                for index in cursor ... last {
                    let finished = forEachWay(of: step, at: children[index], bytes: bytes, state: &state) { state in
                        forEachWay(
                            ofSteps: rest, from: index + 1, limit: nil, of: node, bytes: bytes, state: &state, body)
                    }
                    guard finished else { return false }
                }
                return true
        }
    }

    /// Calls `body` once for each way `steps`, whose first is a quantified step, match `node`'s children from `cursor`
    /// on, as tree-sitter's quantifiers match (ts_query__parse_pattern and ts_query_cursor__advance, lib/src/query.c).
    ///
    /// `?` takes one child after the cursor, or none. `*` and `+` take a run of adjacent children that each match the
    /// inner pattern, after any children they skip: the step repeats through a pass-through step whose copy seeks an
    /// immediate match (`seeking_immediate_match`), so any other sibling, an anonymous one too, ends the run. `*` may
    /// take none. Of the ways that differ only in how much the step takes, tree-sitter keeps the longer: a run starts
    /// where the child before it cannot join it, and a way that takes none or stops a run short sets `limit` for the
    /// steps after it (``forEachWay(ofSteps:from:limit:of:bytes:state:_:)``). A child joins with the first way it
    /// matches the inner pattern.
    // swiftlint:disable:next function_parameter_count function_body_length
    private static func forEachRun(
        ofSteps steps: ArraySlice<QueryPattern>,
        from cursor: Int,
        limit: Int?,
        of node: SyntaxNode,
        bytes: Span<UInt8>,
        state: inout MatchState,
        _ body: (inout MatchState) -> Bool
    ) -> Bool {
        guard case .quantified(let inner, let quantifier) = steps.first else { return true }
        let rest = steps.dropFirst()
        let children = node.children
        // How each child from the cursor on matches the inner pattern, if it does, found once for every run.
        var childWays: [Way?] = []
        childWays.reserveCapacity(children.count - cursor)
        for child in children[cursor...] {
            childWays.append(firstWay(of: inner, at: child, bytes: bytes, state: &state))
        }
        func way(at index: Int) -> Way? {
            index < children.count ? childWays[index - cursor] : nil
        }

        if quantifier != .oneOrMore {
            // No child: the steps after may not go past a child this step could take.
            let firstMatch = childWays.firstIndex { $0 != nil }.map { $0 + cursor }
            let skipLimit = [limit, firstMatch].compactMap(\.self).min()
            guard forEachWay(ofSteps: rest, from: cursor, limit: skipLimit, of: node, bytes: bytes, state: &state, body)
            else { return false }
        }
        let lastStart = min(limit ?? children.count - 1, children.count - 1)
        guard cursor <= lastStart else { return true }
        for start in cursor ... lastStart {
            guard let first = way(at: start) else { continue }
            if quantifier == .optional {
                let finished = state.with(first) { state in
                    forEachWay(ofSteps: rest, from: start + 1, limit: nil, of: node, bytes: bytes, state: &state, body)
                }
                guard finished else { return false }
                continue
            }
            // A run starts where the child before it cannot join it, or the longer run that it joins is the way.
            if start > cursor, way(at: start - 1) != nil { continue }
            let captureCount = state.captures.count
            let predicateCount = state.predicates.count
            state.captures.append(contentsOf: first.captures)
            state.predicates.append(contentsOf: first.predicates)
            var end = start
            var finished: Bool
            while true {
                let next = end + 1
                guard let following = way(at: next) else {
                    finished = forEachWay(
                        ofSteps: rest, from: next, limit: nil, of: node, bytes: bytes, state: &state, body)
                    break
                }
                // The run may stop short of the next child only for steps after it that take that very child.
                finished = forEachWay(
                    ofSteps: rest, from: next, limit: next, of: node, bytes: bytes, state: &state, body)
                guard finished else { break }
                state.captures.append(contentsOf: following.captures)
                state.predicates.append(contentsOf: following.predicates)
                end = next
            }
            state.captures.removeSubrange(captureCount...)
            state.predicates.removeSubrange(predicateCount...)
            guard finished else { return false }
        }
        return true
    }

    /// The captures and predicates of the first way `pattern` matches `node`, or nil when it does not.
    private static func firstWay(
        of pattern: QueryPattern, at node: SyntaxNode, bytes: Span<UInt8>, state: inout MatchState
    ) -> Way? {
        let captureCount = state.captures.count
        let predicateCount = state.predicates.count
        var first: Way?
        _ = forEachWay(of: pattern, at: node, bytes: bytes, state: &state) { state in
            first = Way(
                captures: Array(state.captures[captureCount...]),
                predicates: Array(state.predicates[predicateCount...]))
            return false
        }
        return first
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
}

// MARK: - Ways

extension QueryMatcher {
    /// The captures and predicates of the way being matched, pushed as the way goes deeper into its pattern and popped
    /// as it backs out, so every way of a walk shares the two buffers.
    private struct MatchState {
        var captures: [QueryMatch.Capture] = []
        var predicates: [Predicate] = []

        /// Calls `body` with `capture` of `node` pushed, when there is one, and pops it after.
        mutating func with(
            _ capture: QueryPattern.Capture?, of node: SyntaxNode, _ body: (inout MatchState) -> Bool
        ) -> Bool {
            guard let capture else { return body(&self) }
            captures.append(QueryMatch.Capture(node: node, name: capture.name, index: capture.index))
            defer { captures.removeLast() }
            return body(&self)
        }

        /// Calls `body` with `way`'s captures and predicates pushed, and pops them after.
        mutating func with(_ way: Way, _ body: (inout MatchState) -> Bool) -> Bool {
            let captureCount = captures.count
            let predicateCount = predicates.count
            captures.append(contentsOf: way.captures)
            predicates.append(contentsOf: way.predicates)
            defer {
                captures.removeSubrange(captureCount...)
                predicates.removeSubrange(predicateCount...)
            }
            return body(&self)
        }
    }

    /// One way a pattern matched a node: its captures, and the predicates they must pass.
    private struct Way {
        var captures: [QueryMatch.Capture]
        var predicates: [Predicate]
    }

    /// Keeps, of the ways one pattern matched one node, those tree-sitter's cursor keeps: it drops a way that captures
    /// the same nodes as an earlier one, or only some of the nodes another way captures, the "longest-match criteria"
    /// of ts_query_cursor__advance, which compares ways with ts_query_cursor__compare_captures (lib/src/query.c). The
    /// ways left keep their order.
    ///
    /// - Complexity: O(w) hashing for w ways that all capture as many nodes; O(w²) comparisons otherwise.
    private static func removeShorterWays(_ ways: inout [Way]) {
        var keep = [Bool](repeating: true, count: ways.count)
        // Ways that capture as many nodes can only repeat each other: find the repeats by a hash of their captures.
        var firstWayByHash: [Int: [Int]] = [:]
        for (index, way) in ways.enumerated() {
            let hash = captureHash(of: way.captures)
            if let earlier = firstWayByHash[hash],
                earlier.contains(where: { captures(ways[$0].captures, contain: way.captures, strictly: false) })
            {
                keep[index] = false
            } else {
                firstWayByHash[hash, default: []].append(index)
            }
        }
        // A way that captures fewer nodes than another may capture some of them.
        let counts = ways.map(\.captures.count)
        if let fewest = counts.min(), let most = counts.max(), fewest < most {
            for shorter in ways.indices where keep[shorter] {
                for longer in ways.indices
                where keep[longer] && counts[longer] > counts[shorter]
                    && captures(ways[longer].captures, contain: ways[shorter].captures, strictly: true)
                {
                    keep[shorter] = false
                    break
                }
            }
        }
        ways = ways.indices.filter { keep[$0] }.map { ways[$0] }
    }

    /// A hash of `captures` as a multiset: the same whatever their order.
    private static func captureHash(of captures: [QueryMatch.Capture]) -> Int {
        var sum = 0
        for capture in captures {
            var hasher = Hasher()
            hasher.combine(capture.index)
            hasher.combine(capture.node.byteRange)
            sum &+= hasher.finalize()
        }
        return sum
    }

    /// Whether every capture of `shorter` is one of `longer`'s, each matched once: the same capture of the same node.
    /// With `strictly` false, `longer` must hold nothing else, so the two capture the same nodes.
    private static func captures(
        _ longer: [QueryMatch.Capture], contain shorter: [QueryMatch.Capture], strictly: Bool
    ) -> Bool {
        guard strictly ? longer.count > shorter.count : longer.count == shorter.count else { return false }
        var used = [Bool](repeating: false, count: longer.count)
        for capture in shorter {
            guard
                let match = longer.indices.first(where: {
                    !used[$0] && longer[$0].index == capture.index && longer[$0].node == capture.node
                })
            else { return false }
            used[match] = true
        }
        return true
    }
}
