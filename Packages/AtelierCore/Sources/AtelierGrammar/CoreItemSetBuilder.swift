/// Builds LR(0) core states, then propagates lookaheads through their transitions.
/// Equal cores share one state unless merging introduces a reduce/reduce conflict.
enum CoreItemSetBuilder {
    /// A production position, with the lookaheads stored separately so equal LR(0) cores merge.
    struct CoreItem: Hashable {
        var rule: Int
        var dot: Int
    }

    /// The states LALR propagation gives lookaheads to, and the lookahead terminals their bit sets index.
    struct PropagatedStates: Sendable {
        var states: [LookaheadItemSet]
        var terminals: [String]
    }

    static func build(
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits,
        onPhase: ((String) -> Void)? = nil
    ) throws(GrammarError) -> (PropagatedStates, [Int: [(symbol: String, target: Int)]]) {
        let start = CoreItem(rule: 0, dot: 0)
        let startSet = try coreClosure(
            [start], productions: productions, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
        var cores = [startSet]
        var stateIndex: [[CoreItem]: Int] = [[start]: 0]
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
                // A state is its kernel's closure, and the kernel is the closure's items past their first step, so
                // the kernel finds the state without the closure, the costliest step, being built again.
                let key = kernel.sorted { ($0.rule, $0.dot) < ($1.rule, $1.dot) }
                let targetIdx: Int
                if let existing = stateIndex[key] {
                    targetIdx = existing
                } else {
                    let gotoSet = try coreClosure(
                        kernel, productions: productions, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
                    targetIdx = cores.count
                    guard targetIdx < limits.maxStates else {
                        throw .resourceLimitExceeded(
                            "Parser state construction exceeded limit (\(targetIdx + 1) states, limit \(limits.maxStates))"
                        )
                    }
                    cores.append(gotoSet)
                    stateIndex[key] = targetIdx
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
        onPhase?("LR(0) cores")
        let merged = try propagateLookaheads(
            through: cores, transitions: transitions, productions: productions,
            firstSets: firstSets, rulesByNonTerminal: rulesByNonTerminal, limits: limits)
        onPhase?("lookahead propagation")
        guard merged.states.contains(where: { hasCompetingReductions($0, productions: productions) }) else {
            return (merged, transitions)
        }
        let split = try ConflictSafeCoreMerger.build(
            cores: cores, transitions: transitions, states: merged,
            inputs: .init(
                productions: productions, firstSets: firstSets,
                rulesByNonTerminal: rulesByNonTerminal, limits: limits),
            onPhase: onPhase)
        onPhase?("conflict-safe splitting")
        return split
    }

    /// Whether `state` has competing completed rules: two that end with a lookahead in common.
    static func hasCompetingReductions(
        _ state: LookaheadItemSet, productions: [(name: String, symbols: [String])]
    ) -> Bool {
        var seen = [UInt64](repeating: 0, count: state.wordCount)
        for (index, item) in state.items.enumerated()
        where item.rule != 0 && item.dot == productions[item.rule].symbols.count {
            for (word, bits) in state.lookaheadWords(ofItemAt: index).enumerated() {
                if seen[word] & bits != 0 { return true }
                seen[word] |= bits
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

    /// The lookaheads LALR propagation gives the items of `cores`: the end of the input to the start item, and along
    /// `transitions` and closures, FIRST of what follows an item, and the item's own lookaheads where that can be empty.
    ///
    /// Items are numbered densely, each state's in rule then position order, and lookaheads are bit sets over the
    /// terminals, so propagation reads and writes flat arrays. An item that gets no lookahead is left out of its state.
    ///
    /// - Throws: `GrammarError.resourceLimitExceeded` when the item and lookahead pairs pass
    ///   `limits.maxLookaheadItems`; `.invalidRuleType` when the FIRST sets name no end of input.
    /// - Complexity: O((i + e) · w) per pass over i items and e propagation edges with w words per set; a location is
    ///   passed over each time its set grows.
    static func propagateLookaheads(
        through cores: [Set<CoreItem>],
        transitions: [Int: [(symbol: String, target: Int)]],
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> PropagatedStates {
        let terminals = try LookaheadTerminals(firstSets: firstSets)
        let locations = ItemLocations(cores: cores)
        guard !cores.isEmpty, let start = locations.location(of: CoreItem(rule: 0, dot: 0), in: 0) else {
            return PropagatedStates(states: [], terminals: terminals.names)
        }
        var suffixFirsts = SuffixFirsts(productions: productions, terminals: terminals)
        let edges = PropagationEdges(
            locations: locations, transitions: transitions, productions: productions,
            rulesByNonTerminal: rulesByNonTerminal, suffixFirsts: &suffixFirsts)
        let lookaheads = try edges.propagate(
            from: start, endIndex: terminals.endIndex, suffixFirsts: suffixFirsts, limit: limits.maxLookaheadItems)
        let wordCount = terminals.wordCount
        let states = locations.stateItems.enumerated()
            .map { state, items in
                let offset = locations.offsets[state]
                return LookaheadItemSet(
                    items: items, words: lookaheads[offset * wordCount ..< (offset + items.count) * wordCount],
                    wordCount: wordCount)
            }
        return PropagatedStates(states: states, terminals: terminals.names)
    }
}

/// The items of the LR(0) states numbered densely, each state's in rule then position order: an item's location
/// indexes the flat arrays of lookahead propagation.
struct ItemLocations {
    typealias CoreItem = CoreItemSetBuilder.CoreItem

    /// Each state's items, sorted.
    let stateItems: [[CoreItem]]
    /// The location of each state's first item.
    let offsets: [Int]
    /// The number of items in all states.
    let count: Int

    init(cores: [Set<CoreItem>]) {
        var stateItems: [[CoreItem]] = []
        var offsets: [Int] = []
        stateItems.reserveCapacity(cores.count)
        offsets.reserveCapacity(cores.count)
        var count = 0
        for core in cores {
            let items = core.sorted { ($0.rule, $0.dot) < ($1.rule, $1.dot) }
            offsets.append(count)
            stateItems.append(items)
            count += items.count
        }
        self.stateItems = stateItems
        self.offsets = offsets
        self.count = count
    }

    /// The location of `item` in `state`, found by bisecting the state's sorted items.
    func location(of item: CoreItem, in state: Int) -> Int? {
        let items = stateItems[state]
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if (items[middle].rule, items[middle].dot) < (item.rule, item.dot) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < items.count && items[low] == item ? offsets[state] + low : nil
    }
}

/// The edges lookaheads propagate along, from each item location: to the next state's item past its symbol,
/// forwarding its lookaheads, and to the items its symbol introduces, with FIRST of the rest of its rule, and its
/// lookaheads when that rest can be empty. A location's edges are `starts[location] ..< starts[location + 1]`, each
/// with its target and a code packing its FIRST set and whether it forwards, both in 32 bits.
struct PropagationEdges {
    private var starts: [Int]
    private var targets: [Int32] = []
    private var codes: [Int32] = []

    init(
        locations: ItemLocations,
        transitions: [Int: [(symbol: String, target: Int)]],
        productions: [(name: String, symbols: [String])],
        rulesByNonTerminal: [String: [Int]],
        suffixFirsts: inout SuffixFirsts
    ) {
        starts = [Int](repeating: 0, count: locations.count + 1)
        for (state, items) in locations.stateItems.enumerated() {
            let transitionsBySymbol = Dictionary(
                (transitions[state] ?? []).map { ($0.symbol, $0.target) }, uniquingKeysWith: { first, _ in first })
            for (offset, item) in items.enumerated() {
                starts[locations.offsets[state] + offset] = targets.count
                let symbols = productions[item.rule].symbols
                guard item.dot < symbols.count else { continue }
                let symbol = symbols[item.dot]
                if let target = transitionsBySymbol[symbol],
                    let location = locations.location(
                        of: CoreItemSetBuilder.CoreItem(rule: item.rule, dot: item.dot + 1), in: target)
                {
                    targets.append(Int32(location))
                    codes.append(Self.code(first: nil, forwards: true))
                }
                guard let rules = rulesByNonTerminal[symbol] else { continue }
                let (first, nullable) = suffixFirsts.first(after: item)
                for rule in rules {
                    guard let location = locations.location(of: .init(rule: rule, dot: 0), in: state) else { continue }
                    targets.append(Int32(location))
                    codes.append(Self.code(first: first, forwards: nullable))
                }
            }
        }
        starts[locations.count] = targets.count
    }

    /// Each location's lookaheads, `suffixFirsts.terminals.wordCount` words per location: the end of the input at
    /// `start`, propagated along the edges until no set grows.
    /// - Throws: `GrammarError.resourceLimitExceeded` when the item and lookahead pairs pass `limit`.
    func propagate(
        from start: Int, endIndex: Int, suffixFirsts: SuffixFirsts, limit: Int
    ) throws(GrammarError) -> [UInt64] {
        let wordCount = suffixFirsts.terminals.wordCount
        var lookaheads = [UInt64](repeating: 0, count: (starts.count - 1) * wordCount)
        let end = TerminalBits.position(of: endIndex)
        lookaheads[start * wordCount + end.word] |= end.bit
        var pending = [start]
        var isPending = [Bool](repeating: false, count: starts.count - 1)
        isPending[start] = true
        var itemCount = 1
        while let source = pending.popLast() {
            isPending[source] = false
            for edge in starts[source] ..< starts[source + 1] {
                let target = Int(targets[edge])
                let (first, forwards) = Self.decode(codes[edge])
                var added = 0
                for word in 0 ..< wordCount {
                    let old = lookaheads[target * wordCount + word]
                    var new = old
                    if let first { new |= suffixFirsts.words[first * wordCount + word] }
                    if forwards { new |= lookaheads[source * wordCount + word] }
                    added += (new ^ old).nonzeroBitCount
                    lookaheads[target * wordCount + word] = new
                }
                guard added > 0 else { continue }
                itemCount += added
                guard itemCount <= limit else {
                    throw .resourceLimitExceeded(
                        "Parser lookahead items exceeded limit (\(itemCount) items, limit \(limit))")
                }
                if !isPending[target] {
                    isPending[target] = true
                    pending.append(target)
                }
            }
        }
        return lookaheads
    }

    /// An edge's FIRST set, by number, and whether it forwards its source's lookaheads, in one 32-bit number: 0 for no
    /// set and `n + 1` for set `n`, negated and less one when the edge forwards.
    private static func code(first: Int?, forwards: Bool) -> Int32 {
        let set = Int32((first ?? -1) + 1)
        return forwards ? -1 - set : set
    }

    private static func decode(_ code: Int32) -> (first: Int?, forwards: Bool) {
        let set = code < 0 ? -1 - code : code
        return (set == 0 ? nil : Int(set - 1), code < 0)
    }
}

/// The terminals lookaheads range over, each numbered, and FIRST of each symbol as a bit set over them.
struct LookaheadTerminals: Sendable {
    let names: [String]
    let endIndex: Int
    let wordCount: Int
    /// FIRST of each symbol, `wordCount` words from the offset `firstOffsets` gives, and whether the symbol can be
    /// empty.
    private(set) var firstWords: [UInt64] = []
    private(set) var firstOffsets: [String: (offset: Int, nullable: Bool)] = [:]
    let indices: [String: Int]

    /// - Throws: `GrammarError.invalidRuleType` when no FIRST set holds the end of input.
    init(firstSets: [String: Set<String>]) throws(GrammarError) {
        var terminalNames = Set<String>()
        for first in firstSets.values {
            terminalNames.formUnion(first.filter { $0 != "" })
        }
        names = terminalNames.sorted()
        indices = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        guard let endIndex = indices["$end"] else {
            throw .invalidRuleType("Parser FIRST sets have no end token")
        }
        self.endIndex = endIndex
        wordCount = max((names.count + 63) / 64, 1)
        firstOffsets.reserveCapacity(firstSets.count)
        for (symbol, first) in firstSets {
            let offset = firstWords.count
            firstWords.append(contentsOf: repeatElement(0, count: wordCount))
            for terminal in first {
                guard let index = indices[terminal] else { continue }
                let position = TerminalBits.position(of: index)
                firstWords[offset + position.word] |= position.bit
            }
            firstOffsets[symbol] = (offset, first.contains(""))
        }
    }
}

/// FIRST of the symbols after each item's dot, and whether they can all be empty, computed once per item and kept as
/// numbered bit sets.
struct SuffixFirsts {
    let productions: [(name: String, symbols: [String])]
    let terminals: LookaheadTerminals
    /// The bit sets, `wordCount` words each.
    private(set) var words: [UInt64] = []
    private var known: [CoreItemSetBuilder.CoreItem: (set: Int, nullable: Bool)] = [:]

    init(productions: [(name: String, symbols: [String])], terminals: LookaheadTerminals) {
        self.productions = productions
        self.terminals = terminals
    }

    /// The number of the bit set of FIRST of the symbols after the one at `item`'s dot, and whether they can all be
    /// empty; a symbol without a FIRST set ends the suffix, as one that cannot be empty does.
    mutating func first(after item: CoreItemSetBuilder.CoreItem) -> (set: Int, nullable: Bool) {
        if let computed = known[item] { return computed }
        let wordCount = terminals.wordCount
        let set = words.count / wordCount
        words.append(contentsOf: repeatElement(0, count: wordCount))
        var nullable = true
        for symbol in productions[item.rule].symbols.dropFirst(item.dot + 1) {
            guard let first = terminals.firstOffsets[symbol] else {
                nullable = false
                break
            }
            for word in 0 ..< wordCount {
                words[set * wordCount + word] |= terminals.firstWords[first.offset + word]
            }
            guard first.nullable else {
                nullable = false
                break
            }
        }
        known[item] = (set, nullable)
        return (set, nullable)
    }
}
