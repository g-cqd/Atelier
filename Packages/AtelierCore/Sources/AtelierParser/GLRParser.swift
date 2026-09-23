public import AtelierGrammar

/// GLR parser: forks on a conflict, keeps every fork reducing, and merges stacks that reach the same state history.
public final class GLRParser: Sendable {
    private let parseTable: ParseTable
    private let lexTable: LexTable
    private let productions: [ProductionRule]
    /// O(1) terminal name -> index lookup.
    private let terminalIndex: [String: Int]
    /// O(1) non-terminal name -> index lookup.
    private let nonTerminalIndex: [String: Int]

    public init(parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule]) {
        self.parseTable = parseTable
        self.lexTable = lexTable
        self.productions = productions
        var tIdx = [String: Int](minimumCapacity: parseTable.terminals.count)
        for (i, t) in parseTable.terminals.enumerated() {
            tIdx[t] = i
        }
        self.terminalIndex = tIdx
        var ntIdx = [String: Int](minimumCapacity: parseTable.nonTerminals.count)
        for (i, nt) in parseTable.nonTerminals.enumerated() {
            ntIdx[nt] = i
        }
        self.nonTerminalIndex = ntIdx
    }

    private static let maxStacks = 256
    private static let maxTokens = 100_000

    /// Parse source text and produce a syntax tree.
    ///
    /// A token the table cannot take on a stack becomes an ERROR node there, and the parse goes on. Every token runs
    /// its reductions with a budget, so a table that reduces in a cycle cannot hang the parse.
    ///
    /// - Throws: `ParseError.parsingFailed` beyond 100,000 tokens.
    /// - Complexity: O(t · s · (b + d)) for t tokens, s live stacks (at most 256), b reductions per token and stack
    ///   (at most the table's state count plus the stack's depth d), and d for merging stacks.
    public func parse(
        _ source: String,
        externalScanner: (any ExternalScanner)? = nil
    ) throws(ParseError) -> SyntaxTree {
        let lexer = Lexer(lexTable: lexTable, externalScanner: externalScanner)
        let tokens = lexer.tokenize(source)
        let nonExtraTokens = tokens.filter { !$0.isExtra }

        guard nonExtraTokens.count <= Self.maxTokens else {
            throw .parsingFailed(
                "Token count \(nonExtraTokens.count) exceeds limit \(Self.maxTokens)")
        }

        guard !nonExtraTokens.isEmpty else {
            // Empty input
            return SyntaxTree(
                root: SyntaxNode(type: productions.first?.name ?? "source", byteRange: 0 ..< 0),
                source: source
            )
        }

        var stacks = [ParseStack(state: 0)]
        for (tokenIdx, token) in nonExtraTokens.enumerated() {
            stacks = try advance(consume stacks, past: token, at: tokenIdx)
        }
        if let endIdx = terminalIndex["$end"] {
            stacks = applyReduces(to: consume stacks, lookahead: endIdx)
        }

        // Pick the best stack (prefer one with fewer errors)
        guard let best = stacks.min(by: { $0.errorCount < $1.errorCount }) else {
            throw .parsingFailed("No valid parse at the end of input")
        }

        var root = buildRootNode(from: best, source: source)

        // Insert extra comment tokens into the tree so query matchers can find them
        let extraComments = tokens.filter { $0.isExtra && $0.type == "comment" }
        if !extraComments.isEmpty {
            for token in extraComments {
                root.children.append(
                    SyntaxNode(
                        type: "comment",
                        byteRange: token.byteRange,
                        pointRange: token.pointRange,
                        isExtra: true,
                        isNamed: true
                    ))
            }
            root.children.sort { $0.byteRange.lowerBound < $1.byteRange.lowerBound }
        }

        return SyntaxTree(root: root, source: source)
    }

    // MARK: - Private

    /// Moves every stack past `token`: its reductions, then its shift, then merging and pruning.
    private func advance(
        _ stacks: consuming [ParseStack],
        past token: Lexer.Token,
        at tokenIndex: Int
    ) throws(ParseError) -> [ParseStack] {
        guard let lookahead = terminalIndex[token.type] else {
            // Unknown token — wrap in error node and continue
            var marked = consume stacks
            let node = SyntaxNode(
                type: token.type,
                byteRange: token.byteRange,
                pointRange: token.pointRange,
                isError: true,
                isNamed: false
            )
            for index in marked.indices {
                marked[index].pushNode(node)
            }
            return marked
        }

        var next = ParseStack.mergingIdenticalHistories(
            shift(applyReduces(to: consume stacks, lookahead: lookahead), token: token, lookahead: lookahead))
        guard !next.isEmpty else {
            throw .parsingFailed("No valid parse at token \(tokenIndex): \(token.type)")
        }
        // Prune stacks if count exceeds limit — keep stacks with fewest errors
        if next.count > Self.maxStacks {
            next.sort { $0.errorCount < $1.errorCount }
            next.removeLast(next.count - Self.maxStacks)
        }
        return next
    }

    /// Runs every reduction `lookahead` calls for and returns the stacks ready to shift it or, at the end of the
    /// input, to accept it.
    ///
    /// A fork keeps reducing like any stack, and the forks of a conflict come out, fully reduced, before the stack
    /// that forked when that stack can also shift. A stack and its forks share a budget of reductions: one per state
    /// of the table plus one per node on the stack. A stack still reducing when the budget runs out comes out as it
    /// is, and the shift phase takes the lookahead as an error for it.
    ///
    /// Stacks are popped off the worklist, so each is the only owner of its arrays and a reduction rewrites them in
    /// place; only a fork copies them.
    private func applyReduces(to stacks: consuming [ParseStack], lookahead: Int) -> [ParseStack] {
        var origins = consume stacks
        origins.reverse()
        var ready: [ParseStack] = []
        ready.reserveCapacity(origins.count)
        while let origin = origins.popLast() {
            var budget = parseTable.stateCount + origin.nodes.count
            var pending = [consume origin]
            // Stacks that can shift the lookahead after their forks are done reducing.
            var waiting: [ParseStack] = []
            while var stack = pending.popLast() {
                switch parseTable.actions[stack.state][lookahead] {
                    case .reduce(let rule, let count, let nonTerminal) where budget > 0:
                        budget -= 1
                        if reduce(&stack, rule: rule, count: count, nonTerminal: nonTerminal) {
                            pending.append(stack)
                        } else {
                            ready.append(stack)
                        }

                    case .conflict(let actions) where budget > 0:
                        var forks: [ParseStack] = []
                        for case .reduce(let rule, let count, let nonTerminal) in actions where budget > 0 {
                            budget -= 1
                            var fork = stack
                            if reduce(&fork, rule: rule, count: count, nonTerminal: nonTerminal) {
                                forks.append(fork)
                            }
                        }
                        let canShift = actions.contains { if case .shift = $0 { true } else { false } }
                        if canShift || forks.isEmpty {
                            waiting.append(stack)
                        }
                        pending.append(contentsOf: forks.reversed())

                    default:
                        ready.append(stack)
                }
            }
            ready.append(contentsOf: waiting.reversed())
        }
        return ready
    }

    /// Shifts `token` onto every stack whose state allows it, forking when several shifts do. A stack that cannot
    /// shift it keeps its state and takes the token as an ERROR node: error recovery skips the token for that stack.
    private func shift(_ stacks: consuming [ParseStack], token: Lexer.Token, lookahead: Int) -> [ParseStack] {
        var pending = consume stacks
        pending.reverse()
        var shifted: [ParseStack] = []
        shifted.reserveCapacity(pending.count)
        let leaf = SyntaxNode(
            type: token.type,
            byteRange: token.byteRange,
            pointRange: token.pointRange,
            isNamed: false
        )
        while var stack = pending.popLast() {
            let shiftTargets: [Int]
            switch parseTable.actions[stack.state][lookahead] {
                case .shift(let nextState):
                    stack.pushNode(leaf)
                    stack.state = nextState
                    shifted.append(stack)
                    continue
                case .accept:
                    shifted.append(stack)
                    continue
                case .conflict(let actions):
                    shiftTargets = actions.compactMap { action -> Int? in
                        if case .shift(let nextState) = action { return nextState }
                        return nil
                    }
                case .reduce, .error:
                    shiftTargets = []
            }
            guard let lastTarget = shiftTargets.last else {
                stack.pushNode(
                    SyntaxNode(type: "ERROR", byteRange: token.byteRange, pointRange: token.pointRange, isError: true))
                shifted.append(stack)
                continue
            }
            // Forks copy the stack; the last shift takes it over.
            for nextState in shiftTargets.dropLast() {
                var fork = stack
                fork.pushNode(leaf)
                fork.state = nextState
                shifted.append(fork)
            }
            stack.pushNode(leaf)
            stack.state = lastTarget
            shifted.append(stack)
        }
        return shifted
    }

    /// Replaces the top `count` nodes of `stack` with one `nonTerminal` node built by production `rule`, and moves to
    /// the table's GOTO state from the state the first of those nodes was pushed in. Without that GOTO state the
    /// reduction is an error: returns false and leaves `stack` as it was.
    private func reduce(_ stack: inout ParseStack, rule: Int, count: Int, nonTerminal: String) -> Bool {
        guard let nonTerminalIdx = nonTerminalIndex[nonTerminal],
            let target = parseTable.gotos[stack.state(poppingNodes: count)][nonTerminalIdx]
        else {
            return false
        }
        let children = stack.popNodes(count)

        let byteStart = children.first?.byteRange.lowerBound ?? 0
        let byteEnd = children.last?.byteRange.upperBound ?? 0
        let pointStart = children.first?.pointRange.lowerBound ?? .zero
        let pointEnd = children.last?.pointRange.upperBound ?? .zero
        var nodeFields: [String: [SyntaxNode]] = [:]

        for (idx, fieldName) in productionFields(for: rule) where idx < children.count {
            nodeFields[fieldName, default: []].append(children[idx])
        }

        stack.pushNode(
            SyntaxNode(
                type: nonTerminal,
                children: children,
                byteRange: byteStart ..< byteEnd,
                pointRange: pointStart ..< pointEnd,
                fields: nodeFields,
                isNamed: true
            ))
        stack.state = target
        return true
    }

    private func productionFields(for ruleIndex: Int) -> [Int: String] {
        guard productions.indices.contains(ruleIndex) else { return [:] }
        return productions[ruleIndex].fields
    }

    private func buildRootNode(from stack: ParseStack, source: String) -> SyntaxNode {
        if stack.nodes.count == 1 {
            return stack.nodes[0]
        }
        let byteEnd = source.utf8.count
        return SyntaxNode(
            type: productions.first?.name ?? "source",
            children: stack.nodes,
            byteRange: 0 ..< byteEnd,
            pointRange: .zero ..< Point(row: 0, column: byteEnd),
            isNamed: true
        )
    }
}
