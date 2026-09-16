public import KittyGrammar

/// GLR parser: handles ambiguous grammars by forking on conflict and merging on reduce.
public final class GLRParser: Sendable {
    private let parseTable: ParseTable
    private let lexTable: LexTable
    private let productions: [ProductionRule]
    /// O(1) terminal name -> index lookup (replaces linear firstIndex(of:) scans).
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
                root: SyntaxNode(type: productions.first?.name ?? "source", byteRange: 0..<0),
                source: source
            )
        }

        // Run GLR parse with potentially multiple stacks
        var stacks: [ParseStack] = [ParseStack(state: 0)]

        for (tokenIdx, token) in nonExtraTokens.enumerated() {
            guard let termIdx = terminalIndex[token.type] else {
                // Unknown token — wrap in error node and continue
                stacks = stacks.map { stack in
                    var s = stack
                    s.pushNode(
                        SyntaxNode(
                            type: token.type,
                            byteRange: token.byteRange,
                            pointRange: token.pointRange,
                            isError: true,
                            isNamed: false
                        ))
                    return s
                }
                continue
            }

            // Apply reduces first (before shift)
            stacks = applyReduces(stacks: stacks, terminalIndex: termIdx)

            // Apply shifts
            var newStacks: [ParseStack] = []
            for var stack in stacks {
                let action = parseTable.actions[stack.state][termIdx]
                switch action {
                case .shift(let nextState):
                    stack.pushNode(
                        SyntaxNode(
                            type: token.type,
                            byteRange: token.byteRange,
                            pointRange: token.pointRange,
                            isNamed: false
                        ))
                    stack.state = nextState
                    newStacks.append(stack)

                case .conflict(let actions):
                    for act in actions {
                        if case .shift(let nextState) = act {
                            var forked = stack
                            forked.pushNode(
                                SyntaxNode(
                                    type: token.type,
                                    byteRange: token.byteRange,
                                    pointRange: token.pointRange,
                                    isNamed: false
                                ))
                            forked.state = nextState
                            newStacks.append(forked)
                        }
                    }

                case .accept:
                    newStacks.append(stack)

                case .reduce, .error:
                    // Error recovery: skip token
                    var errStack = stack
                    errStack.pushNode(
                        SyntaxNode(
                            type: "ERROR",
                            byteRange: token.byteRange,
                            pointRange: token.pointRange,
                            isError: true
                        ))
                    newStacks.append(errStack)
                }
            }

            stacks = newStacks
            guard !stacks.isEmpty else {
                throw .parsingFailed("No valid parse at token \(tokenIdx): \(token.type)")
            }
            // Prune stacks if count exceeds limit — keep stacks with fewest errors
            if stacks.count > Self.maxStacks {
                stacks.sort { $0.errorCount < $1.errorCount }
                stacks = Array(stacks.prefix(Self.maxStacks))
            }
        }

        // Check for accept on $end
        if let endIdx = terminalIndex["$end"] {
            stacks = applyReduces(stacks: stacks, terminalIndex: endIdx)
        }

        // Pick the best stack (prefer one with fewer errors)
        let best = stacks.min(by: { $0.errorCount < $1.errorCount }) ?? stacks[0]

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

    private func applyReduces(stacks: [ParseStack], terminalIndex termIdx: Int) -> [ParseStack] {
        var result: [ParseStack] = []

        for var stack in stacks {
            var shouldAppendStack = true

            reduceLoop: while true {
                let action = parseTable.actions[stack.state][termIdx]

                switch action {
                case .reduce(let ruleIndex, let count, let nonTerminal):
                    stack = performReduce(
                        stack: stack, ruleIndex: ruleIndex, count: count, nonTerminal: nonTerminal)
                    continue reduceLoop

                case .conflict(let actions):
                    // Fork: one stack per reduce action
                    for act in actions {
                        if case .reduce(let ri, let c, let nt) = act {
                            let forked = performReduce(
                                stack: stack, ruleIndex: ri, count: c, nonTerminal: nt)
                            result.append(forked)
                        }
                    }
                    if actions.contains(where: {
                        if case .shift = $0 { return true }
                        return false
                    }) {
                        result.append(stack)
                    }
                    shouldAppendStack = false
                    break reduceLoop

                default:
                    break reduceLoop
                }
            }

            if shouldAppendStack {
                result.append(stack)
            }
        }

        return result
    }

    private func performReduce(stack: ParseStack, ruleIndex: Int, count: Int, nonTerminal: String)
        -> ParseStack
    {
        var s = stack
        let children = s.popNodes(count)

        let byteStart = children.first?.byteRange.lowerBound ?? 0
        let byteEnd = children.last?.byteRange.upperBound ?? 0
        let pointStart = children.first?.pointRange.lowerBound ?? .zero
        let pointEnd = children.last?.pointRange.upperBound ?? .zero
        var nodeFields: [String: [SyntaxNode]] = [:]

        for (idx, fieldName) in productionFields(for: ruleIndex) where idx < children.count {
            nodeFields[fieldName, default: []].append(children[idx])
        }

        let node = SyntaxNode(
            type: nonTerminal,
            children: children,
            byteRange: byteStart..<byteEnd,
            pointRange: pointStart..<pointEnd,
            fields: nodeFields,
            isNamed: true
        )

        s.pushNode(node)

        // Apply GOTO using dictionary lookup
        if let ntIdx = nonTerminalIndex[nonTerminal],
            let gotoState = parseTable.gotos[s.stateBeforeTop][ntIdx]
        {
            s.state = gotoState
        }

        return s
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
            byteRange: 0..<byteEnd,
            pointRange: .zero..<Point(row: 0, column: byteEnd),
            isNamed: true
        )
    }
}
