import AtelierGrammar

/// Which lookaheads a stack can actually take, from the stack's own states rather than its top state's row alone.
///
/// The compiler merges LR(1) states that share a core, so a state's row reduces on the lookaheads of every context it
/// stands for. A lookahead valid only in another context makes the stack reduce and then fail to shift. Tree-sitter
/// never merges states when that would make an external token valid, and its external scanners rely on that: they
/// read a token wherever `validSymbols` allows it. Running the reductions on the stack's states, as the parse would,
/// gives the stack's exact set without a state more in the table.
extension GLRParser {
    /// The external tokens `stack` can take, in the grammar's order: those its state's row allows whose reductions,
    /// run on the stack's states, end in a shift. An external the grammar lists among its extras stays valid: it can
    /// come anywhere.
    /// - Complexity: O(e · r) for e externals the row allows and r reductions each calls for.
    func viableExternals(for stack: ParseStack) -> [Bool] {
        var valid = parseTable.validExternals[stack.state]
        for index in valid.indices where valid[index] && !parseTable.externalIsExtra[index] {
            guard let terminal = terminalIndex[parseTable.externalSymbols[index]] else { continue }
            valid[index] = canShift(terminal, on: stack)
        }
        return valid
    }

    /// Whether `stack` shifts, or accepts, the lookahead `terminal` once it has run the reductions the lookahead calls
    /// for, on any branch of a conflict. The reductions run on a copy of the stack's states and no node is built.
    /// A reduction without a GOTO state fails its branch, and so does running out of the budget `applyReduces` has.
    func canShift(_ terminal: Int, on stack: ParseStack) -> Bool {
        switch parseTable.actions[stack.state][terminal] {
            case .shift, .accept: return true
            case .error: return false
            case .reduce, .conflict: break
        }
        var budget = parseTable.stateCount + stack.nodes.count
        return canShift(terminal, from: VirtualStates(states: stack.states, nodes: stack.nodes), budget: &budget)
    }

    /// Whether the reduction of `count` symbols to `nonTerminal` leads `stack` to shift `terminal`, as
    /// ``canShift(_:on:)`` runs it: when it does not, the reduction was made by merged lookaheads, and the parser takes
    /// the shift precedence set against it (``ParseTable/lostShifts``).
    func reductionShifts(_ terminal: Int, on stack: ParseStack, count: Int, nonTerminal: String) -> Bool {
        var states = VirtualStates(states: stack.states, nodes: stack.nodes)
        guard states.reduce(count: count, to: nonTerminal, in: self) else { return false }
        var budget = parseTable.stateCount + stack.nodes.count
        return canShift(terminal, from: states, budget: &budget)
    }

    /// The target of the shift of `terminal` that precedence resolved against in `state`, if it did.
    func lostShift(of terminal: Int, in state: Int) -> Int? {
        parseTable.lostShifts[state]?[terminal]
    }

    private func canShift(_ terminal: Int, from states: VirtualStates, budget: inout Int) -> Bool {
        var states = states
        while budget > 0 {
            budget -= 1
            // Whether the reduction there shifts the token or leads nowhere, the parser shifts it.
            if lostShift(of: terminal, in: states.top) != nil { return true }
            switch parseTable.actions[states.top][terminal] {
                case .shift, .accept:
                    return true
                case .error:
                    return false
                case .reduce(_, let count, let nonTerminal):
                    guard states.reduce(count: count, to: nonTerminal, in: self) else { return false }
                case .conflict(let actions):
                    for action in actions {
                        switch action {
                            case .shift, .accept:
                                return true
                            case .reduce(_, let count, let nonTerminal):
                                var branch = states
                                if branch.reduce(count: count, to: nonTerminal, in: self),
                                    canShift(terminal, from: branch, budget: &budget)
                                {
                                    return true
                                }
                            case .error, .conflict:
                                continue
                        }
                    }
                    return false
            }
        }
        return false
    }

    /// The target of the GOTO on `nonTerminal` from `state`, if the table has one.
    fileprivate func gotoState(from state: Int, on nonTerminal: String) -> Int? {
        nonTerminalIndex[nonTerminal].flatMap { parseTable.gotos[state][$0] }
    }
}

/// A stack's states as reductions change them, the stack's own arrays untouched: the nodes still standing from it, and
/// the states pushed since, one per symbol a reduction made.
private struct VirtualStates {
    /// The stack's states: the one each node was pushed in, then the current one.
    let states: [Int]
    /// The stack's nodes; a skipped token's ERROR node among them is no symbol, and no reduction counts it.
    let nodes: [SyntaxNode]
    /// How many of the stack's nodes still stand.
    var standing: Int
    var pushed: [Int] = []

    init(states: [Int], nodes: [SyntaxNode]) {
        self.states = states
        self.nodes = nodes
        standing = nodes.count
    }

    var top: Int { pushed.last ?? states[standing] }

    /// Pops `count` symbols as `ParseStack.popSymbols` does, skipped tokens aside, and pushes the GOTO state from the
    /// state then on top; false when the table has none.
    mutating func reduce(count: Int, to nonTerminal: String, in parser: GLRParser) -> Bool {
        var remaining = max(count, 0)
        let fromPushed = min(remaining, pushed.count)
        pushed.removeLast(fromPushed)
        remaining -= fromPushed
        if remaining > 0 {
            while standing > 0, nodes[standing - 1].isError { standing -= 1 }
            while standing > 0, remaining > 0 {
                standing -= 1
                if !nodes[standing].isError { remaining -= 1 }
            }
        }
        guard let target = parser.gotoState(from: top, on: nonTerminal) else { return false }
        pushed.append(target)
        return true
    }
}
