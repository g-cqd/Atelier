import KittyGrammar
import os

/// GLR parser: handles ambiguous grammars by forking on conflict and merging on reduce.
public final class GLRParser: Sendable {
    private let parseTable: ParseTable
    private let lexTable: LexTable
    private let productions: [ProductionRule]

    public init(parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule]) {
        self.parseTable = parseTable
        self.lexTable = lexTable
        self.productions = productions
    }

    /// Parse source text and produce a syntax tree.
    public func parse(_ source: String) throws(ParseError) -> SyntaxTree {
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize(source)
        let nonExtraTokens = tokens.filter { !$0.isExtra }

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
            guard let termIdx = parseTable.terminals.firstIndex(of: token.type) else {
                // Unknown token — wrap in error node and continue
                stacks = stacks.map { stack in
                    var s = stack
                    s.pushNode(SyntaxNode(
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
                    stack.pushNode(SyntaxNode(
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
                            forked.pushNode(SyntaxNode(
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
                    errStack.pushNode(SyntaxNode(
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
        }

        // Check for accept on $end
        if let endIdx = parseTable.terminals.firstIndex(of: "$end") {
            stacks = applyReduces(stacks: stacks, terminalIndex: endIdx)
        }

        // Pick the best stack (prefer one with fewer errors)
        let best = stacks.min(by: { $0.errorCount < $1.errorCount }) ?? stacks[0]

        let root = buildRootNode(from: best, source: source)
        return SyntaxTree(root: root, source: source)
    }

    // MARK: - Private

    private func applyReduces(stacks: [ParseStack], terminalIndex: Int) -> [ParseStack] {
        var result: [ParseStack] = []

        for var stack in stacks {
            var shouldAppendStack = true

            reduceLoop: while true {
                let action = parseTable.actions[stack.state][terminalIndex]

                switch action {
                case .reduce(let ruleIndex, let count, let nonTerminal):
                    stack = performReduce(stack: stack, ruleIndex: ruleIndex, count: count, nonTerminal: nonTerminal)
                    continue reduceLoop

                case .conflict(let actions):
                    // Fork: one stack per reduce action
                    for act in actions {
                        if case .reduce(let ri, let c, let nt) = act {
                            let forked = performReduce(stack: stack, ruleIndex: ri, count: c, nonTerminal: nt)
                            result.append(forked)
                        }
                    }
                    if actions.contains(where: { if case .shift = $0 { return true }; return false }) {
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

    private func performReduce(stack: ParseStack, ruleIndex: Int, count: Int, nonTerminal: String) -> ParseStack {
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

        // Apply GOTO
        if let ntIdx = parseTable.nonTerminals.firstIndex(of: nonTerminal),
           let gotoState = parseTable.gotos[s.stateBeforeTop][ntIdx] {
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

// MARK: - Parse Stack

private let parseStackCounter = OSAllocatedUnfairLock(initialState: 0)

struct ParseStack: Sendable {
    let id: Int
    var state: Int
    var stateStack: [Int]
    var nodes: [SyntaxNode]
    var errorCount: Int

    var stateBeforeTop: Int {
        stateStack.last ?? 0
    }

    init(state: Int) {
        self.id = parseStackCounter.withLock { val in
            let current = val
            val += 1
            return current
        }
        self.state = state
        self.stateStack = [state]
        self.nodes = []
        self.errorCount = 0
    }

    mutating func pushNode(_ node: SyntaxNode) {
        stateStack.append(state)
        nodes.append(node)
        if node.isError { errorCount += 1 }
    }

    mutating func popNodes(_ count: Int) -> [SyntaxNode] {
        guard count > 0 else { return [] }
        let popped = Array(nodes.suffix(count))
        nodes.removeLast(min(count, nodes.count))
        for _ in 0..<min(count, stateStack.count - 1) {
            stateStack.removeLast()
        }
        state = stateStack.last ?? 0
        return popped
    }
}
