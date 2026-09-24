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
        /// The rules each lookahead, by number, completes.
        var reductions: [Int: Set<Int>]
    }

    static func build(
        cores initialCores: [Set<CoreItemSetBuilder.CoreItem>],
        transitions initialTransitions: [Int: [(symbol: String, target: Int)]],
        states initialStates: CoreItemSetBuilder.PropagatedStates,
        inputs: Inputs,
        onPhase: ((String) -> Void)? = nil
    ) throws(GrammarError) -> (CoreItemSetBuilder.PropagatedStates, [Int: [(symbol: String, target: Int)]]) {
        var cores = initialCores
        var transitions = initialTransitions
        var propagated = initialStates
        let terminals = try LookaheadTerminals(firstSets: inputs.firstSets)
        var suffixFirsts = SuffixFirsts(productions: inputs.productions, terminals: terminals)
        var transitionCount = transitions.values.reduce(0) { $0 + $1.count }
        var round = 0

        while true {
            round += 1
            var incoming = [[Incoming]](repeating: [], count: cores.count)
            for source in cores.indices {
                for (index, edge) in (transitions[source] ?? []).enumerated() {
                    incoming[edge.target].append(Incoming(source: source, index: index, symbol: edge.symbol))
                }
            }

            var split = false
            // Every clone receives a subset of its original core's lookaheads, so only original cores need revisiting.
            for state in initialCores.indices
            where incoming[state].count > 1
                && CoreItemSetBuilder.hasCompetingReductions(propagated.states[state], productions: inputs.productions)
            {
                var groups: [Group] = []
                for edge in incoming[state] {
                    let reductions = try reductions(
                        from: propagated.states[edge.source], through: edge.symbol,
                        targetCore: cores[state], inputs: inputs, suffixFirsts: &suffixFirsts)
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
            onPhase?("split round \(round) grouping")
            guard split else { return (propagated, transitions) }
            propagated = try CoreItemSetBuilder.propagateLookaheads(
                through: cores, transitions: transitions, productions: inputs.productions,
                firstSets: inputs.firstSets, rulesByNonTerminal: inputs.rulesByNonTerminal, limits: inputs.limits)
            onPhase?("split round \(round) propagation")
        }
    }

    /// The rules the items `source` moves on `symbol` into a state of `targetCore` complete there, by lookahead
    /// number: the kernel's completed items, and, when the core holds empty productions, those of the kernel's closure.
    private static func reductions(
        from source: LookaheadItemSet, through symbol: String,
        targetCore: Set<CoreItemSetBuilder.CoreItem>,
        inputs: Inputs, suffixFirsts: inout SuffixFirsts
    ) throws(GrammarError) -> [Int: Set<Int>] {
        typealias CoreItem = CoreItemSetBuilder.CoreItem
        let wordCount = source.wordCount
        var lookaheads: [CoreItem: [UInt64]] = [:]
        for (index, item) in source.items.enumerated() {
            let symbols = inputs.productions[item.rule].symbols
            guard item.dot < symbols.count, symbols[item.dot] == symbol else { continue }
            lookaheads[CoreItem(rule: item.rule, dot: item.dot + 1)] = Array(source.lookaheadWords(ofItemAt: index))
        }
        if targetCore.contains(where: { $0.dot == 0 && inputs.productions[$0.rule].symbols.isEmpty }) {
            try close(&lookaheads, inputs: inputs, suffixFirsts: &suffixFirsts, wordCount: wordCount)
        }
        var completed: [Int: Set<Int>] = [:]
        for (item, words) in lookaheads
        where item.rule != 0 && item.dot == inputs.productions[item.rule].symbols.count {
            for (word, bits) in words.enumerated() {
                var remaining = bits
                while remaining != 0 {
                    completed[word << 6 | remaining.trailingZeroBitCount, default: []].insert(item.rule)
                    remaining &= remaining - 1
                }
            }
        }
        return completed
    }

    /// Adds to `lookaheads` the items their items introduce, each with FIRST of what follows the symbol that
    /// introduces it, and that item's lookaheads where that can be empty, as an LR(1) closure does.
    /// - Throws: `GrammarError.resourceLimitExceeded` past `maxLookaheadItems` item and lookahead pairs.
    private static func close(
        _ lookaheads: inout [CoreItemSetBuilder.CoreItem: [UInt64]], inputs: Inputs,
        suffixFirsts: inout SuffixFirsts, wordCount: Int
    ) throws(GrammarError) {
        var pairCount = lookaheads.values.reduce(0) { total, words in
            total + words.reduce(0) { $0 + $1.nonzeroBitCount }
        }
        var pending = Array(lookaheads.keys)
        while let item = pending.popLast() {
            let symbols = inputs.productions[item.rule].symbols
            guard item.dot < symbols.count, let rules = inputs.rulesByNonTerminal[symbols[item.dot]] else { continue }
            let (first, nullable) = suffixFirsts.first(after: item)
            var introduced = Array(suffixFirsts.words[first * wordCount ..< (first + 1) * wordCount])
            if nullable, let own = lookaheads[item] {
                for word in 0 ..< wordCount { introduced[word] |= own[word] }
            }
            for rule in rules {
                let target = CoreItemSetBuilder.CoreItem(rule: rule, dot: 0)
                var words = lookaheads[target] ?? [UInt64](repeating: 0, count: wordCount)
                var added = 0
                for word in 0 ..< wordCount {
                    let merged = words[word] | introduced[word]
                    added += (merged ^ words[word]).nonzeroBitCount
                    words[word] = merged
                }
                // An item that gets no lookahead is no LR(1) item at all, as the kernel's items all have some.
                guard added > 0 else { continue }
                pairCount += added
                guard pairCount <= inputs.limits.maxLookaheadItems else {
                    throw .resourceLimitExceeded(
                        "Parser state exceeded item limit (\(pairCount) items, limit \(inputs.limits.maxLookaheadItems))"
                    )
                }
                lookaheads[target] = words
                pending.append(target)
            }
        }
    }

    private static func introducesConflict(
        _ existing: [Int: Set<Int>], _ added: [Int: Set<Int>]
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
