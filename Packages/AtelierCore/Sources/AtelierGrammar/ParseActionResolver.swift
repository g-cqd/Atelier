/// Fills a parse table's actions from its core-merged LR states, choosing between a shift and the reductions that
/// compete with it the way tree-sitter does.
///
/// Reductions for a lookahead are taken in rule order: one of higher precedence replaces those before it, one of lower
/// precedence is left out. Against them, a shift's precedence is that of the items that would shift the lookahead past
/// their first step: the precedence at their dot. A shift of higher precedence wins, a lower one loses, and at equal
/// precedence the reductions' associativity decides, left for the reductions and right for the shift. Two integer
/// precedences compare as numbers; otherwise the grammar's `precedences` lists order two names, or a name and the rules
/// the lists name, earlier over later. Anything else stays a conflict, and the parser forks: tree-sitter too keeps the
/// actions precedence leaves, and the grammar's `conflicts` only declares which may remain.
struct ParseActionResolver {
    let productions: [FlatProduction]
    let firstSets: [String: Set<String>]
    /// The grammar's `precedences`: each list orders its names and rules, earlier over later.
    let precedences: [[PrecedenceEntry]]

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

        var reductions = Reductions()
        for rule in completedRules.sorted() {
            let last = productions[rule].steps.last
            reductions.insert(
                rule, symbol: productions[rule].name, precedence: last?.precedence ?? 0,
                associativity: last?.associativity, resolver: self)
        }
        let reduceActions = reductions.rules.map { rule in
            Action.reduce(ruleIndex: rule, count: productions[rule].steps.count, nonTerminal: productions[rule].name)
        }

        guard let shift else {
            return reduceActions.count == 1 ? reduceActions[0] : .conflict(reduceActions)
        }
        guard !reductions.rules.isEmpty else { return .shift(shift) }

        switch winner(shifting: lookahead, in: itemSet, against: reductions) {
            case .shift:
                return .shift(shift)
            case .reductions:
                return reduceActions.count == 1 ? reduceActions[0] : .conflict(reduceActions)
            case .neither:
                return .conflict(reduceActions + [.shift(shift)])
        }
    }

    /// The reductions kept for one lookahead, and what the shift competes against: the precedence of the last one kept,
    /// the rules kept, and their associativities.
    private struct Reductions {
        var rules: [Int] = []
        var precedence: Precedence = 0
        var symbols: [String] = []
        var hasLeft = false
        var hasRight = false
        var hasNone = false

        /// Adds the reduction of `rule` as tree-sitter inserts a reduction: it replaces the reductions of lower
        /// precedence, is left out against higher, and joins those it neither beats nor loses to.
        mutating func insert(
            _ rule: Int, symbol: String, precedence: Precedence, associativity: Associativity?,
            resolver: ParseActionResolver
        ) {
            if !rules.isEmpty {
                switch resolver.compare(precedence, [symbol], self.precedence, symbols) {
                    case .higher:
                        self = Reductions()
                    case .same:
                        break
                    case .lower:
                        return
                }
            }
            rules.append(rule)
            self.precedence = precedence
            if !symbols.contains(symbol) { symbols.append(symbol) }
            switch associativity {
                case .left: hasLeft = true
                case .right: hasRight = true
                case nil: hasNone = true
            }
        }
    }

    private enum Winner {
        case shift
        case reductions
        case neither
    }

    /// How one precedence compares with another.
    enum PrecedenceOrder {
        case lower
        case same
        case higher
    }

    private func winner(shifting lookahead: String, in itemSet: ItemSet, against reductions: Reductions) -> Winner {
        var shiftIsHigher = false
        var shiftIsLower = false
        for item in itemSet.items where item.dotPosition > 0 {
            let steps = productions[item.ruleIndex].steps
            guard item.dotPosition < steps.count,
                firstSets[steps[item.dotPosition].symbol]?.contains(lookahead) ?? false
            else { continue }
            switch compare(
                steps[item.dotPosition - 1].precedence, [productions[item.ruleIndex].name], reductions.precedence,
                reductions.symbols)
            {
                case .higher: shiftIsHigher = true
                case .lower: shiftIsLower = true
                case .same: break
            }
        }
        if shiftIsHigher != shiftIsLower {
            return shiftIsHigher ? .shift : .reductions
        }
        guard !shiftIsHigher else { return .neither }

        // Only reductions that all group the same way decide; a mix, or one without associativity, does not.
        switch (reductions.hasLeft, reductions.hasNone, reductions.hasRight) {
            case (true, false, false): return .reductions
            case (false, false, true): return .shift
            default: return .neither
        }
    }

    /// How `left`, the precedence of a rule among `leftSymbols`, compares with `right`, as tree-sitter compares them:
    /// two integers, one of them not 0, as numbers; anything else by the first of the grammar's `precedences` lists
    /// that names both, earlier over later, a list naming a rule of `leftSymbols` or `rightSymbols` as well as a name;
    /// the same when no list orders them.
    func compare(
        _ left: Precedence, _ leftSymbols: [String], _ right: Precedence, _ rightSymbols: [String]
    ) -> PrecedenceOrder {
        if case .integer(let leftValue) = left, case .integer(let rightValue) = right, leftValue != 0 || rightValue != 0
        {
            return leftValue == rightValue ? .same : leftValue < rightValue ? .lower : .higher
        }
        for list in precedences {
            var sawLeft = false
            var sawRight = false
            for entry in list {
                if Self.entry(entry, matches: left, of: leftSymbols) {
                    sawLeft = true
                    if sawRight { return .lower }
                } else if Self.entry(entry, matches: right, of: rightSymbols) {
                    sawRight = true
                    if sawLeft { return .higher }
                }
            }
        }
        return .same
    }

    /// Whether `entry` of a precedence list stands for `precedence`, or for one of `symbols`, the rules it applies to.
    private static func entry(_ entry: PrecedenceEntry, matches precedence: Precedence, of symbols: [String]) -> Bool {
        switch entry {
            case .literal(let name): precedence == .name(name)
            case .symbol(let name): symbols.contains(name)
        }
    }
}
