/// Builds LR(0) core states, then propagates lookaheads through their transitions.
/// Equal cores share one state unless merging introduces a reduce/reduce conflict.
enum CoreItemSetBuilder {
    /// A production position, with the lookaheads stored separately so equal LR(0) cores merge.
    struct CoreItem: Hashable {
        var rule: Int
        var dot: Int
    }

    private struct ItemLocation: Hashable {
        var state: Int
        var item: CoreItem
    }

    private struct Propagation {
        var target: ItemLocation
        var spontaneous: Set<Int> = []
        var forwardsLookaheads = false
    }

    private struct FirstEntry {
        var terminals: Set<Int>
        var nullable: Bool
    }

    static func build(
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> ([ItemSet], [Int: [(symbol: String, target: Int)]]) {
        let start = CoreItem(rule: 0, dot: 0)
        let startSet = try coreClosure(
            [start], productions: productions, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
        var cores = [startSet]
        var setIndex: [Set<CoreItem>: Int] = [startSet: 0]
        var transitions: [Int: [(symbol: String, target: Int)]] = [:]
        var worklist = [0]
        var transitionCount = 0

        while let stateIdx = worklist.popLast() {
            var kernels: [String: Set<CoreItem>] = [:]
            for item in cores[stateIdx] {
                let symbols = productions[item.rule].symbols
                guard item.dot < symbols.count else { continue }
                kernels[symbols[item.dot], default: []].insert(CoreItem(rule: item.rule, dot: item.dot + 1))
            }
            for symbol in kernels.keys.sorted() {
                guard let kernel = kernels[symbol] else { continue }
                let gotoSet = try coreClosure(
                    kernel, productions: productions, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
                let targetIdx: Int
                if let existing = setIndex[gotoSet] {
                    targetIdx = existing
                } else {
                    targetIdx = cores.count
                    guard targetIdx < limits.maxStates else {
                        throw .resourceLimitExceeded(
                            "Parser state construction exceeded limit (\(targetIdx + 1) states, limit \(limits.maxStates))"
                        )
                    }
                    cores.append(gotoSet)
                    setIndex[gotoSet] = targetIdx
                    worklist.append(targetIdx)
                }
                transitions[stateIdx, default: []].append((symbol: symbol, target: targetIdx))
                transitionCount += 1
                guard transitionCount <= limits.maxTransitions else {
                    throw .resourceLimitExceeded(
                        "Parser transitions exceeded limit (\(transitionCount) transitions, limit \(limits.maxTransitions))"
                    )
                }
            }
        }
        let merged = try propagateLookaheads(
            through: cores, transitions: transitions, productions: productions,
            firstSets: firstSets, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
        guard hasCompetingReductions(merged, productions: productions) else { return (merged, transitions) }
        return try ConflictSafeCoreMerger.build(
            cores: cores, transitions: transitions, states: merged,
            inputs: .init(
                productions: productions, firstSets: firstSets,
                rulesByNonTerminal: rulesByNonTerminal, limits: limits))
    }

    /// Whether a merged core has competing completed rules on one lookahead.
    private static func hasCompetingReductions(
        _ states: [ItemSet], productions: [(name: String, symbols: [String])]
    ) -> Bool {
        for state in states {
            var completed: [String: Int] = [:]
            for item in state.items
            where item.ruleIndex != 0
                && item.dotPosition == productions[item.ruleIndex].symbols.count
            {
                if let prior = completed[item.lookahead], prior != item.ruleIndex { return true }
                completed[item.lookahead] = item.ruleIndex
            }
        }
        return false
    }

    private static func coreClosure(
        _ kernel: Set<CoreItem>,
        productions: [(name: String, symbols: [String])],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> Set<CoreItem> {
        var result = kernel
        var pending = Array(kernel)
        while let item = pending.popLast() {
            let symbols = productions[item.rule].symbols
            guard item.dot < symbols.count,
                let rules = rulesByNonTerminal[symbols[item.dot]]
            else { continue }
            for rule in rules {
                let introduced = CoreItem(rule: rule, dot: 0)
                if result.insert(introduced).inserted {
                    guard result.count <= limits.maxItemsPerState else {
                        throw .resourceLimitExceeded(
                            "Parser state exceeded item limit (\(result.count) items, limit \(limits.maxItemsPerState))"
                        )
                    }
                    pending.append(introduced)
                }
            }
        }
        return result
    }

    static func propagateLookaheads(
        through cores: [Set<CoreItem>],
        transitions: [Int: [(symbol: String, target: Int)]],
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> [ItemSet] {
        let (names, endIndex, numberedFirst) = try indexFirstSets(firstSets)

        var edges: [ItemLocation: [Propagation]] = [:]
        for (state, items) in cores.enumerated() {
            let transitionsBySymbol = Dictionary(
                uniqueKeysWithValues: (transitions[state] ?? [])
                    .map {
                        ($0.symbol, $0.target)
                    })
            for item in items {
                let symbols = productions[item.rule].symbols
                guard item.dot < symbols.count else { continue }
                let source = ItemLocation(state: state, item: item)
                let symbol = symbols[item.dot]
                if let target = transitionsBySymbol[symbol] {
                    edges[source, default: []]
                        .append(
                            Propagation(
                                target: ItemLocation(state: target, item: CoreItem(rule: item.rule, dot: item.dot + 1)),
                                forwardsLookaheads: true))
                }
                guard let rules = rulesByNonTerminal[symbol] else { continue }
                let (first, nullable) = firstOfSuffix(
                    symbols.dropFirst(item.dot + 1), firstSets: numberedFirst)
                for rule in rules {
                    edges[source, default: []]
                        .append(
                            Propagation(
                                target: ItemLocation(state: state, item: CoreItem(rule: rule, dot: 0)),
                                spontaneous: first, forwardsLookaheads: nullable))
                }
            }
        }

        let start = ItemLocation(state: 0, item: CoreItem(rule: 0, dot: 0))
        var lookaheads: [ItemLocation: Set<Int>] = [start: [endIndex]]
        var pending = [start]
        var enqueued: Set<ItemLocation> = [start]
        var itemCount = 1
        while let source = pending.popLast() {
            enqueued.remove(source)
            let current = lookaheads[source] ?? []
            for edge in edges[source] ?? [] {
                var destination = lookaheads[edge.target, default: []]
                let before = destination.count
                destination.formUnion(edge.spontaneous)
                if edge.forwardsLookaheads { destination.formUnion(current) }
                guard destination.count != before else { continue }
                itemCount += destination.count - before
                guard itemCount <= limits.maxLookaheadItems else {
                    throw .resourceLimitExceeded(
                        "Parser lookahead items exceeded limit (\(itemCount) items, limit \(limits.maxLookaheadItems))"
                    )
                }
                lookaheads[edge.target] = destination
                if enqueued.insert(edge.target).inserted {
                    pending.append(edge.target)
                }
            }
        }
        return cores.enumerated()
            .map { state, items in
                var expanded: Set<LRItem> = []
                for item in items {
                    let location = ItemLocation(state: state, item: item)
                    for lookahead in lookaheads[location] ?? [] {
                        expanded.insert(
                            LRItem(ruleIndex: item.rule, dotPosition: item.dot, lookahead: names[lookahead]))
                    }
                }
                return ItemSet(items: expanded)
            }
    }
    /// Assigns one integer to each possible lookahead before propagation.
    private static func indexFirstSets(
        _ firstSets: [String: Set<String>]
    ) throws(GrammarError) -> (names: [String], endIndex: Int, entries: [String: FirstEntry]) {
        var terminalNames = Set<String>()
        for first in firstSets.values {
            terminalNames.formUnion(first.filter { $0 != "" })
        }
        let names = terminalNames.sorted()
        let terminalIndex = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        guard let endIndex = terminalIndex["$end"] else {
            throw .invalidRuleType("Parser FIRST sets have no end token")
        }
        var numberedFirst: [String: FirstEntry] = [:]
        numberedFirst.reserveCapacity(firstSets.count)
        for (symbol, first) in firstSets {
            numberedFirst[symbol] = FirstEntry(
                terminals: Set(first.compactMap { terminalIndex[$0] }), nullable: first.contains(""))
        }

        return (names, endIndex, numberedFirst)
    }

    /// FIRST of the symbols after an LR item, and whether they can all be empty.
    private static func firstOfSuffix(
        _ symbols: ArraySlice<String>, firstSets: [String: FirstEntry]
    ) -> (Set<Int>, Bool) {
        var first: Set<Int> = []
        for symbol in symbols {
            guard let next = firstSets[symbol] else { return (first, false) }
            first.formUnion(next.terminals)
            if !next.nullable { return (first, false) }
        }
        return (first, true)
    }
}
