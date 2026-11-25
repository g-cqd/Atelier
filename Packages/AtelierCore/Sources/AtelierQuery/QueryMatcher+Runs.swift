internal import AtelierParser

// Matching runs of siblings, the first way through a pattern, and text predicates; apart from the type's file, to keep
// its type body within the 300 lines SwiftLint allows.
extension QueryMatcher {
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
    static func forEachRun(
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
                        ofSteps: rest,
                        from: next,
                        limit: nil,
                        of: node,
                        bytes: bytes,
                        state: &state,
                        body
                    )
                    break
                }
                // The run may stop short of the next child only for steps after it that take that very child.
                finished = forEachWay(
                    ofSteps: rest,
                    from: next,
                    limit: next,
                    of: node,
                    bytes: bytes,
                    state: &state,
                    body
                )
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
    static func firstWay(
        of pattern: QueryPattern,
        at node: SyntaxNode,
        bytes: Span<UInt8>,
        state: inout MatchState
    ) -> Way? {
        let captureCount = state.captures.count
        let predicateCount = state.predicates.count
        var first: Way?
        _ = forEachWay(of: pattern, at: node, bytes: bytes, state: &state) { state in
            first = Way(
                captures: Array(state.captures[captureCount...]),
                predicates: Array(state.predicates[predicateCount...])
            )
            return false
        }
        return first
    }

    /// Whether `node`'s bytes in the source are `value`'s UTF-8, compared in place, byte for byte, as tree-sitter
    /// compares a token's text: no string is built for the node, and a node that reaches outside the source matches
    /// nothing.
    /// - Complexity: O(1) when the lengths differ; O(`value`'s UTF-8 length) otherwise.
    static func bytes(of node: SyntaxNode, in source: Span<UInt8>, equal value: String) -> Bool {
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
