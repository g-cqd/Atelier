/// Separates incoming LR(1) contexts only where joining their LR(0) cores creates a reduction conflict.
enum ConflictSafeCoreMerger {
    struct Inputs {
        var productions: [(name: String, symbols: [String])]
        var firstSets: [String: Set<String>]
        var rulesByNonTerminal: [String: [Int]]
        var limits: GrammarCompilationLimits
    }

    private struct Incoming {
        var source: Int
        var index: Int
        var symbol: String
    }

    private struct Group {
        var incoming: [Incoming]
        var reductions: [String: Set<Int>]
    }

    static func build(
        cores initialCores: [Set<CoreItemSetBuilder.CoreItem>],
        transitions initialTransitions: [Int: [(symbol: String, target: Int)]],
        states initialStates: [ItemSet],
        inputs: Inputs
    ) throws(GrammarError) -> ([ItemSet], [Int: [(symbol: String, target: Int)]]) {
        var cores = initialCores
        var transitions = initialTransitions
        var states = initialStates
        var transitionCount = transitions.values.reduce(0) { $0 + $1.count }

        while true {
            var incoming = [[Incoming]](repeating: [], count: cores.count)
            for source in cores.indices {
                for (index, edge) in (transitions[source] ?? []).enumerated() {
                    incoming[edge.target].append(Incoming(source: source, index: index, symbol: edge.symbol))
                }
            }

            var split = false
            // Every clone receives a subset of its original core's lookaheads, so only original cores need revisiting.
            for state in initialCores.indices
            where hasCompetingReductions(states[state], productions: inputs.productions) {
                guard incoming[state].count > 1 else { continue }
                var groups: [Group] = []
                for edge in incoming[state] {
                    let reductions = try reductions(
                        from: states[edge.source], through: edge.symbol,
                        targetCore: cores[state], inputs: inputs)
                    if let index = groups.firstIndex(where: { !introducesConflict($0.reductions, reductions) }) {
                        groups[index].incoming.append(edge)
                        for (lookahead, rules) in reductions {
                            groups[index].reductions[lookahead, default: []].formUnion(rules)
                        }
                    } else {
                        groups.append(Group(incoming: [edge], reductions: reductions))
                    }
                }
                guard groups.count > 1 else { continue }
                guard cores.count + groups.count - 1 <= inputs.limits.maxStates else {
                    throw .resourceLimitExceeded(
                        "Parser state construction exceeded limit (\(cores.count + groups.count - 1) states, limit \(inputs.limits.maxStates))"
                    )
                }
                for group in groups.dropFirst() {
                    let clone = cores.count
                    let outgoing = transitions[state] ?? []
                    guard transitionCount + outgoing.count <= inputs.limits.maxTransitions else {
                        throw .resourceLimitExceeded(
                            "Parser transitions exceeded limit (\(transitionCount + outgoing.count) transitions, limit \(inputs.limits.maxTransitions))"
                        )
                    }
                    cores.append(cores[state])
                    transitions[clone] = outgoing
                    transitionCount += outgoing.count
                    for edge in group.incoming {
                        transitions[edge.source]?[edge.index].target = clone
                    }
                }
                split = true
            }
            guard split else { return (states, transitions) }
            states = try CoreItemSetBuilder.propagateLookaheads(
                through: cores, transitions: transitions, productions: inputs.productions,
                firstSets: inputs.firstSets, rulesByNonTerminal: inputs.rulesByNonTerminal, limits: inputs.limits)
        }
    }

    private static func hasCompetingReductions(
        _ state: ItemSet, productions: [(name: String, symbols: [String])]
    ) -> Bool {
        var reductions: [String: Int] = [:]
        for item in state.items
        where item.ruleIndex != 0
            && item.dotPosition == productions[item.ruleIndex].symbols.count
        {
            if let prior = reductions[item.lookahead], prior != item.ruleIndex { return true }
            reductions[item.lookahead] = item.ruleIndex
        }
        return false
    }

    private static func reductions(
        from source: ItemSet, through symbol: String,
        targetCore: Set<CoreItemSetBuilder.CoreItem>,
        inputs: Inputs
    ) throws(GrammarError) -> [String: Set<Int>] {
        let needsClosure = targetCore.contains {
            $0.dot == 0 && inputs.productions[$0.rule].symbols.isEmpty
        }
        let items: Set<LRItem>
        if needsClosure {
            var relaxed = inputs.limits
            relaxed.maxItemsPerState = inputs.limits.maxLookaheadItems
            items =
                try source.goto(
                    symbol: symbol, productions: inputs.productions, firstSets: inputs.firstSets,
                    rulesByNonTerminal: inputs.rulesByNonTerminal, limits: relaxed
                )
                .items
        } else {
            items = Set(
                source.items.compactMap { item in
                    let symbols = inputs.productions[item.ruleIndex].symbols
                    guard item.dotPosition < symbols.count, symbols[item.dotPosition] == symbol else { return nil }
                    return LRItem(
                        ruleIndex: item.ruleIndex, dotPosition: item.dotPosition + 1,
                        lookahead: item.lookahead)
                })
        }
        var completed: [String: Set<Int>] = [:]
        for item in items
        where item.ruleIndex != 0
            && item.dotPosition == inputs.productions[item.ruleIndex].symbols.count
        {
            completed[item.lookahead, default: []].insert(item.ruleIndex)
        }
        return completed
    }

    private static func introducesConflict(
        _ existing: [String: Set<Int>], _ added: [String: Set<Int>]
    ) -> Bool {
        for (lookahead, rules) in added {
            guard let prior = existing[lookahead] else { continue }
            for first in prior where !rules.contains(first) {
                if rules.contains(where: { !prior.contains($0) }) { return true }
            }
        }
        return false
    }
}
