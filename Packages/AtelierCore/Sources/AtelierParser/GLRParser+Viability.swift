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
        return canShift(terminal, from: VirtualStates(states: stack.states), budget: &budget)
    }

    private func canShift(_ terminal: Int, from states: VirtualStates, budget: inout Int) -> Bool {
        var states = states
        while budget > 0 {
            budget -= 1
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

/// A stack's states as reductions change them, the stack's own array untouched: the states still standing from it, and
/// the states pushed since, one per symbol a reduction made.
private struct VirtualStates {
    /// The stack's states: the one each node was pushed in, then the current one.
    let states: [Int]
    /// How many of the stack's nodes still stand.
    var standing: Int
    var pushed: [Int] = []

    init(states: [Int]) {
        self.states = states
        standing = states.count - 1
    }

    var top: Int { pushed.last ?? states[standing] }

    /// Pops `count` nodes as `ParseStack.popNodes` does, and pushes the GOTO state from the state then on top; false
    /// when the table has none.
    mutating func reduce(count: Int, to nonTerminal: String, in parser: GLRParser) -> Bool {
        var remaining = max(count, 0)
        let fromPushed = min(remaining, pushed.count)
        pushed.removeLast(fromPushed)
        remaining -= fromPushed
        standing -= min(remaining, standing)
        guard let target = parser.gotoState(from: top, on: nonTerminal) else { return false }
        pushed.append(target)
        return true
    }
}
