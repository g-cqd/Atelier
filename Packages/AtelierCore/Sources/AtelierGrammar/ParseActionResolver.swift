/// Fills a parse table's actions from its LR(1) states, choosing between a shift and the reductions that compete
/// with it the way tree-sitter does.
///
/// Among the reductions for a lookahead, only those of the highest precedence stay. Against them, a shift's
/// precedence is that of the items that would shift the lookahead past their first step: the precedence at their
/// dot. A shift of higher precedence wins, a lower one loses, and at equal precedence the reductions' associativity
/// decides, left for the reductions and right for the shift. Anything else stays a conflict, and the parser forks.
struct ParseActionResolver {
    let productions: [FlatProduction]
    let firstSets: [String: Set<String>]

    /// The table of `itemSets` and their `transitions`, over `terminals` then `nonTerminals`.
    func parseTable(
        itemSets: [ItemSet],
        transitions: [Int: [(symbol: String, target: Int)]],
        terminals: [String],
        nonTerminals: [String]
    ) -> ParseTable {
        let terminalIndex = Dictionary(uniqueKeysWithValues: terminals.enumerated().map { ($1, $0) })
        let nonTerminalIndex = Dictionary(uniqueKeysWithValues: nonTerminals.enumerated().map { ($1, $0) })

        var actions = [[Action]](
            repeating: [Action](repeating: .error, count: terminals.count), count: itemSets.count)
        var gotos = [[Int?]](
            repeating: [Int?](repeating: nil, count: nonTerminals.count), count: itemSets.count)

        for (state, itemSet) in itemSets.enumerated() {
            var shifts: [Int: Int] = [:]
            for (symbol, target) in transitions[state] ?? [] {
                if let terminal = terminalIndex[symbol] {
                    shifts[terminal] = target
                } else if let nonTerminal = nonTerminalIndex[symbol] {
                    gotos[state][nonTerminal] = target
                }
            }
            var completed: [Int: [Int]] = [:]
            for item in itemSet.items where item.dotPosition == productions[item.ruleIndex].steps.count {
                if let terminal = terminalIndex[item.lookahead] {
                    completed[terminal, default: []].append(item.ruleIndex)
                }
            }
            for terminal in Set(shifts.keys).union(completed.keys) {
                actions[state][terminal] = action(
                    on: terminals[terminal],
                    shift: shifts[terminal],
                    completedRules: completed[terminal] ?? [],
                    in: itemSet
                )
            }
        }

        return ParseTable(
            stateCount: itemSets.count,
            symbols: terminals + nonTerminals,
            terminals: terminals,
            nonTerminals: nonTerminals,
            actions: actions,
            gotos: gotos
        )
    }

    /// The action on `lookahead` in the state of `itemSet`: its shift to `shift`, if any, against the reductions of
    /// `completedRules`, the productions that end there with that lookahead. A conflict lists its reductions by rule
    /// index, then its shift, so the parser forks in the same order on every run.
    private func action(on lookahead: String, shift: Int?, completedRules: [Int], in itemSet: ItemSet) -> Action {
        // The augmented rule's end is the accept.
        guard !completedRules.contains(0) else { return .accept }

        var reductions: [Int] = []
        var reductionPrecedence = Int.min
        for rule in completedRules.sorted() {
            let precedence = productions[rule].steps.last?.precedence ?? 0
            if precedence > reductionPrecedence {
                reductions = []
                reductionPrecedence = precedence
            }
            if precedence == reductionPrecedence {
                reductions.append(rule)
            }
        }
        let reduceActions = reductions.map { rule in
            Action.reduce(ruleIndex: rule, count: productions[rule].steps.count, nonTerminal: productions[rule].name)
        }

        guard let shift else {
            return reduceActions.count == 1 ? reduceActions[0] : .conflict(reduceActions)
        }
        guard !reductions.isEmpty else { return .shift(shift) }

        switch winner(shifting: lookahead, in: itemSet, against: reductions, of: reductionPrecedence) {
            case .shift:
                return .shift(shift)
            case .reductions:
                return reduceActions.count == 1 ? reduceActions[0] : .conflict(reduceActions)
            case .neither:
                return .conflict(reduceActions + [.shift(shift)])
        }
    }

    private enum Winner {
        case shift
        case reductions
        case neither
    }

    private func winner(
        shifting lookahead: String,
        in itemSet: ItemSet,
        against reductions: [Int],
        of reductionPrecedence: Int
    ) -> Winner {
        var shiftIsHigher = false
        var shiftIsLower = false
        for item in itemSet.items where item.dotPosition > 0 {
            let steps = productions[item.ruleIndex].steps
            guard item.dotPosition < steps.count,
                firstSets[steps[item.dotPosition].symbol]?.contains(lookahead) ?? false
            else { continue }
            let precedence = steps[item.dotPosition - 1].precedence
            if precedence > reductionPrecedence { shiftIsHigher = true }
            if precedence < reductionPrecedence { shiftIsLower = true }
        }
        if shiftIsHigher != shiftIsLower {
            return shiftIsHigher ? .shift : .reductions
        }
        guard !shiftIsHigher else { return .neither }

        // Only reductions that all group the same way decide; a mix, or one without associativity, does not.
        let associativities = Set(reductions.map { productions[$0].steps.last?.associativity })
        guard associativities.count == 1, let associativity = associativities.first ?? nil else { return .neither }
        return associativity == .left ? .reductions : .shift
    }
}
