public import AtelierGrammar
import Synchronization

/// GLR parser: forks on a conflict, keeps every fork reducing, and merges stacks that reach the same state history.
public final class GLRParser: Sendable {
    let parseTable: ParseTable
    let lexTable: LexTable
    private let productions: [ProductionRule]
    /// O(1) terminal name -> index lookup.
    let terminalIndex: [String: Int]
    /// O(1) non-terminal name -> index lookup.
    let nonTerminalIndex: [String: Int]
    /// The lex table's automaton laid out for reading; nil for a table without lex modes.
    private let scanner: TokenScanner?
    /// The terminal index of each of the lex table's tokens; nil for an extra, which the table does not take.
    let tokenTerminals: [Int?]
    /// The grammar's symbols in tree-sitter's order, which breaks a tie between two parses.
    let symbolRanks: SymbolRanks
    /// The lex modes built for stacks that can take only some of their state's tokens, by those tokens.
    let viableModes = Mutex<[[Int]: LazyLexMode]>([:])

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
        self.scanner = TokenScanner(lexTable)
        self.tokenTerminals = lexTable.tokens.map { tIdx[$0.name] }
        self.symbolRanks = SymbolRanks(lexTable: lexTable, parseTable: parseTable, productions: productions)
    }

    static let maxStacks = 256
    static let maxTokens = 100_000
    /// The deepest tree a parse builds: well past 5,000 levels of JSON nesting, which take about 15,000 levels of
    /// objects or 10,000 of arrays, and well within what a consumer that still recurses survives on the 8 MB main
    /// thread in a release build.
    static let maxTreeDepth = 16_384
    /// The error a parse throws instead of building a tree deeper than ``maxTreeDepth``.
    static let treeTooDeep = ParseError.tooDeep(limit: maxTreeDepth)
    /// Tokens between two cancellation checks: a cancelled parse stops within this many tokens, lexing included.
    static let cancellationCheckInterval = 256

    /// Parse source text and produce a syntax tree.
    ///
    /// A token the table cannot take on a stack becomes an ERROR node there, and the parse goes on. Every token runs
    /// its reductions with a budget, so a table that reduces in a cycle cannot hang the parse. A parse that would
    /// build a tree more than 16,384 levels deep declines instead; what it built is freed without recursion, so the
    /// decline is safe on a 512 KiB thread stack.
    ///
    /// Synchronous, but it honours the cancellation of the task it runs in: it checks every 256 tokens and stops at
    /// the first check that finds the task cancelled. A table with lex modes reads a token only as the parse needs
    /// it, so a cancelled parse lexes no further either.
    ///
    /// - Throws: `ParseError.tooManyTokens` beyond 100,000 tokens, `.tooDeep` for a tree deeper than 16,384 levels,
    ///   and `.cancelled` when cancelled.
    /// - Complexity: O(t · s · (b + d)) for t tokens, s live stacks (at most 256), b reductions per token and stack
    ///   (at most the table's state count plus the stack's depth d), and d for merging stacks.
    public func parse(
        _ source: String,
        externalScanner: (any GrammarExternalScanner)? = nil
    ) throws(ParseError) -> SyntaxTree {
        try parse(source, externalScanner: externalScanner, isCancelled: { Task.isCancelled })
    }

    /// ``parse(_:externalScanner:)`` with `isCancelled` in place of the task's cancellation.
    ///
    /// With lex modes, the lexer reads each token in the mode of the parser's state, as tree-sitter does, so of two
    /// tokens that overlap, such as JSON's string content and punctuation, it reads the one the parser can take; a
    /// table without them is lexed context-free, all at once.
    func parse(
        _ source: String,
        externalScanner: (any GrammarExternalScanner)?,
        isCancelled: () -> Bool
    ) throws(ParseError) -> SyntaxTree {
        if let externalScanner, let scanner, !parseTable.externalNames.isEmpty {
            guard type(of: externalScanner).externalNames == parseTable.externalNames else {
                throw .parsingFailed("External scanner symbols do not match the grammar")
            }
            try validateExternalTable()
            let outcome = Self.withUTF8(of: source) { utf8 in
                Result { () throws(ParseError) in
                    try parseWithExternals(
                        source, utf8: utf8, scanner: scanner,
                        externalScanner: externalScanner, isCancelled: isCancelled)
                }
            }
            return try outcome.get()
        }
        guard let scanner else {
            let lexer = Lexer(lexTable: lexTable)
            var tokens = TokenizedSource(lexer.tokenize(source), terminalIndex: terminalIndex)
            return try parse(source, from: &tokens, isCancelled: isCancelled)
        }
        let outcome = Self.withUTF8(of: source) { utf8 in
            var tokens = ScannedTokenSource(
                utf8, scanner: scanner, tokens: lexTable.tokens, tokenTerminals: tokenTerminals)
            return Result { () throws(ParseError) in try parse(source, from: &tokens, isCancelled: isCancelled) }
        }
        return try outcome.get()
    }

    /// Parses `source` from the tokens `tokens` reads out of it.
    ///
    /// The cancellation check counts every token read, extras such as comments too, so a file of comments alone
    /// still meets one every 256 tokens; the token limit counts only the tokens the stacks take.
    private func parse(
        _ source: String,
        from tokens: inout some ParseTokenSource,
        isCancelled: () -> Bool
    ) throws(ParseError) -> SyntaxTree {
        var stacks = [ParseStack(state: 0)]
        var extras: [ParseToken] = []
        var readCount = 0
        var tokenIndex = 0
        while let token = tokens.next(for: stacks) {
            if readCount.isMultiple(of: Self.cancellationCheckInterval), isCancelled() {
                ParseStack.releaseAll(&stacks)
                throw .cancelled(atToken: readCount)
            }
            readCount += 1
            guard !token.isExtra else {
                extras.append(token)
                continue
            }
            guard tokenIndex < Self.maxTokens else {
                ParseStack.releaseAll(&stacks)
                throw .tooManyTokens(limit: Self.maxTokens)
            }
            stacks = try advance(consume stacks, past: token, at: tokenIndex)
            tokenIndex += 1
        }

        guard tokenIndex > 0 else {
            // No token but extras, if any: an empty root keeps them, as a parsed one does.
            let root = SyntaxNode(type: productions.first?.name ?? "source", byteRange: 0 ..< 0)
            return SyntaxTree(root: attachingExtras(extras, to: root), source: source, errorByteCount: 0)
        }
        if let endIdx = terminalIndex["$end"] {
            var exceededDepth = false
            stacks = applyReduces(to: consume stacks, lookahead: endIdx, exceededDepth: &exceededDepth)
            guard !exceededDepth else {
                ParseStack.releaseAll(&stacks)
                throw Self.treeTooDeep
            }
        }

        guard let best = ParseStack.takingBest(from: &stacks, ranks: symbolRanks) else {
            throw .parsingFailed("No valid parse at the end of input")
        }
        let errorByteCount = best.errorByteCount
        let root = try buildRootNode(from: consume best, byteCount: source.utf8.count, endPoint: tokens.end)
        return SyntaxTree(
            root: attachingExtras(extras, to: consume root), source: source, errorByteCount: errorByteCount)
    }

    // MARK: - Private

    /// Moves every stack past `token`: its reductions, then its shift, then merging and pruning. Throws
    /// ``treeTooDeep`` when a reduction would build a node deeper than ``maxTreeDepth``, after releasing every stack.
    func advance(
        _ stacks: consuming [ParseStack],
        past token: ParseToken,
        at tokenIndex: Int
    ) throws(ParseError) -> [ParseStack] {
        guard let lookahead = token.terminal else {
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
                marked[index].isRecovering = true
            }
            return marked
        }

        var exceededDepth = false
        var reduced = applyReduces(to: consume stacks, lookahead: lookahead, exceededDepth: &exceededDepth)
        guard !exceededDepth else {
            ParseStack.releaseAll(&reduced)
            throw Self.treeTooDeep
        }
        var next = ParseStack.mergingIdenticalHistories(
            shift(consume reduced, token: token, lookahead: lookahead), ranks: symbolRanks)
        guard !next.isEmpty else {
            throw .parsingFailed("No valid parse at token \(tokenIndex): \(token.type)")
        }
        // Prune stacks if count exceeds limit — keep the preferred ones
        if next.count > Self.maxStacks {
            next.sort { $0.isPreferred(over: $1, ranks: symbolRanks) }
            var pruned = Array(next[Self.maxStacks...])
            next.removeSubrange(Self.maxStacks...)
            for index in pruned.indices {
                pruned[index].releaseNodes(sparing: next[0])
            }
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
    ///
    /// A reduction that would build a node taller than ``maxTreeDepth`` sets `exceededDepth` and stops all reducing:
    /// every stack comes out as it is, for the caller to release.
    func applyReduces(
        to stacks: consuming [ParseStack],
        lookahead: Int,
        exceededDepth: inout Bool
    ) -> [ParseStack] {
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
                guard !exceededDepth else {
                    ready.append(stack)
                    continue
                }
                switch parseTable.actions[stack.state][lookahead] {
                    case .reduce(_, let count, let nonTerminal)
                    where lostShift(of: lookahead, in: stack.state) != nil
                        && !reductionShifts(lookahead, on: stack, count: count, nonTerminal: nonTerminal):
                        // Merged lookaheads made this reduction: the shift phase takes the shift it won against.
                        ready.append(stack)
                    case .reduce(let rule, let count, let nonTerminal) where budget > 0:
                        budget -= 1
                        switch reduce(&stack, rule: rule, count: count, nonTerminal: nonTerminal) {
                            case .reduced: pending.append(stack)
                            case .missingGoto: ready.append(stack)
                            case .tooDeep:
                                exceededDepth = true
                                ready.append(stack)
                        }

                    case .conflict(let actions) where budget > 0:
                        var forks: [ParseStack] = []
                        for case .reduce(let rule, let count, let nonTerminal) in actions where budget > 0 {
                            budget -= 1
                            var fork = stack
                            switch reduce(&fork, rule: rule, count: count, nonTerminal: nonTerminal) {
                                case .reduced: forks.append(fork)
                                case .missingGoto: break
                                case .tooDeep: exceededDepth = true
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
    private func shift(_ stacks: consuming [ParseStack], token: ParseToken, lookahead: Int) -> [ParseStack] {
        var pending = consume stacks
        pending.reverse()
        var shifted: [ParseStack] = []
        shifted.reserveCapacity(pending.count)
        let leaf = SyntaxNode(
            type: token.type,
            byteRange: token.byteRange,
            pointRange: token.pointRange,
            isNamed: token.isNamed
        )
        while var stack = pending.popLast() {
            let shiftTargets: [Int]
            switch parseTable.actions[stack.state][lookahead] {
                case .shift(let nextState):
                    stack.pushNode(leaf)
                    stack.state = nextState
                    stack.isRecovering = false
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
                case .reduce:
                    // A reduction left unmade: the shift precedence set against it, if there was one.
                    shiftTargets = lostShift(of: lookahead, in: stack.state).map { [$0] } ?? []
                case .error:
                    shiftTargets = []
            }
            guard let lastTarget = shiftTargets.last else {
                stack.pushNode(
                    SyntaxNode(type: "ERROR", byteRange: token.byteRange, pointRange: token.pointRange, isError: true))
                stack.isRecovering = true
                shifted.append(stack)
                continue
            }
            // Forks copy the stack; the last shift takes it over.
            for nextState in shiftTargets.dropLast() {
                var fork = stack
                fork.pushNode(leaf)
                fork.state = nextState
                fork.isRecovering = false
                shifted.append(fork)
            }
            stack.pushNode(leaf)
            stack.state = lastTarget
            stack.isRecovering = false
            shifted.append(stack)
        }
        return shifted
    }
}

// MARK: - Reducing

extension GLRParser {
    /// Replaces the top `count` nodes of `stack` with one `nonTerminal` node built by production `rule`, and moves to
    /// the table's GOTO state from the state the first of those nodes was pushed in. Without that GOTO state the
    /// reduction is an error. The node takes the production's fields, its children the production's aliases, and the
    /// stack the production's dynamic precedence.
    ///
    /// The node spans its children; an empty reduction sits where the node below it ends, at the start of the input
    /// if there is none. The nodes on a stack therefore stay in source order, so a node always ends after it starts.
    private func reduce(_ stack: inout ParseStack, rule: Int, count: Int, nonTerminal: String) -> Reduction {
        guard let nonTerminalIdx = nonTerminalIndex[nonTerminal],
            let target = parseTable.gotos[stack.state(poppingSymbols: count)][nonTerminalIdx]
        else {
            return .missingGoto
        }
        let height = stack.height(ofTopSymbols: count) + 1
        guard height <= Self.maxTreeDepth else { return .tooDeep }
        var (children, skippedAbove) = stack.popSymbols(count)
        // The production's steps are its symbols; a skipped token's ERROR node between them takes no step.
        let steps = children.indices.filter { !children[$0].isError }

        let byteRange: Range<Int>
        let pointRange: Range<Point>
        if let first = children.first, let last = children.last {
            byteRange = first.byteRange.lowerBound ..< last.byteRange.upperBound
            pointRange = first.pointRange.lowerBound ..< last.pointRange.upperBound
        } else {
            let byte = stack.nodes.last?.byteRange.upperBound ?? 0
            let point = stack.nodes.last?.pointRange.upperBound ?? .zero
            byteRange = byte ..< byte
            pointRange = point ..< point
        }
        var nodeFields: [String: [SyntaxNode]] = [:]
        var dynamicPrecedence = 0
        if productions.indices.contains(rule) {
            for (step, alias) in productions[rule].aliases where step < steps.count {
                children[steps[step]].type = alias.type
                children[steps[step]].isNamed = alias.isNamed
            }
            for (step, fieldName) in productions[rule].fields where step < steps.count {
                nodeFields[fieldName, default: []].append(children[steps[step]])
            }
            dynamicPrecedence = productions[rule].dynamicPrecedence
        }

        stack.pushNode(
            SyntaxNode(
                type: nonTerminal,
                children: children,
                byteRange: byteRange,
                pointRange: pointRange,
                fields: nodeFields,
                isNamed: true
            ),
            height: height)
        stack.addDynamicPrecedence(dynamicPrecedence)
        stack.state = target
        stack.restoreSkipped(skippedAbove)
        return .reduced
    }
}

// MARK: - Tree Building

extension GLRParser {
    /// The stack's only symbol, with the ERROR nodes of the tokens error recovery skipped around it as children, as
    /// tree-sitter's root holds them; otherwise a node above the stack's nodes spanning the source, `byteCount` bytes
    /// ending at `endPoint`. That extra level must not take the tree past ``maxTreeDepth``: then the parse declines,
    /// freeing the stack.
    func buildRootNode(
        from stack: consuming ParseStack,
        byteCount: Int,
        endPoint: Point
    ) throws(ParseError) -> SyntaxNode {
        if stack.nodes.count == 1 {
            return stack.nodes[0]
        }
        // Indices, not copies: a copy of a deep node outliving the stack would free it recursively.
        let symbols = stack.nodes.indices.filter { !stack.nodes[$0].isError }
        if symbols.count == 1, let symbol = symbols.first {
            var root = stack.nodes[symbol]
            let skipped = stack.nodes.filter(\.isError)
            root.children.append(contentsOf: skipped)
            root.children.sort {
                ($0.byteRange.lowerBound, $0.byteRange.upperBound) < ($1.byteRange.lowerBound, $1.byteRange.upperBound)
            }
            for node in skipped {
                root.byteRange =
                    min(root.byteRange.lowerBound, node.byteRange.lowerBound)
                    ..< max(root.byteRange.upperBound, node.byteRange.upperBound)
                root.pointRange =
                    min(root.pointRange.lowerBound, node.pointRange.lowerBound)
                    ..< max(root.pointRange.upperBound, node.pointRange.upperBound)
            }
            return root
        }
        guard stack.tallestHeight < Self.maxTreeDepth else {
            stack.releaseNodes()
            throw Self.treeTooDeep
        }
        return SyntaxNode(
            type: productions.first?.name ?? "source",
            children: stack.nodes,
            byteRange: 0 ..< byteCount,
            pointRange: .zero ..< endPoint,
            isNamed: true
        )
    }

    /// `root` with an extra child per token of `extras`, such as a comment, in source order, and its ranges widened to
    /// cover them, or a query limited to a comment's range would skip the root with the comment. `extras` is in source
    /// order.
    func attachingExtras(_ extras: [ParseToken], to root: consuming SyntaxNode) -> SyntaxNode {
        guard let first = extras.first, let last = extras.last else { return root }
        for token in extras {
            root.children.append(
                SyntaxNode(
                    type: token.type,
                    byteRange: token.byteRange,
                    pointRange: token.pointRange,
                    isExtra: true,
                    isNamed: token.isNamed
                ))
        }
        root.children.sort {
            ($0.byteRange.lowerBound, $0.byteRange.upperBound) < ($1.byteRange.lowerBound, $1.byteRange.upperBound)
        }
        root.byteRange =
            min(root.byteRange.lowerBound, first.byteRange.lowerBound)
            ..< max(root.byteRange.upperBound, last.byteRange.upperBound)
        root.pointRange =
            min(root.pointRange.lowerBound, first.pointRange.lowerBound)
            ..< max(root.pointRange.upperBound, last.pointRange.upperBound)
        return root
    }
}

/// What `GLRParser.reduce` did to a stack.
private enum Reduction {
    case reduced
    /// The table has no GOTO state for the reduction, an error; the stack is as it was.
    case missingGoto
    /// The node would be taller than ``GLRParser/maxTreeDepth``; the stack is as it was.
    case tooDeep
}
