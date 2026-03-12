// MARK: - LR Item

/// An LR(1) item: a production rule with a dot position and a lookahead terminal.
public struct LRItem: Sendable, Equatable, Hashable {
    public var ruleIndex: Int
    public var dotPosition: Int
    public var lookahead: String

    public init(ruleIndex: Int, dotPosition: Int, lookahead: String) {
        self.ruleIndex = ruleIndex
        self.dotPosition = dotPosition
        self.lookahead = lookahead
    }
}

// MARK: - Item Set

/// A set of LR(1) items (a parser state).
public struct ItemSet: Sendable, Equatable, Hashable {
    public var items: Set<LRItem>

    public init(items: Set<LRItem> = []) {
        self.items = items
    }

    /// Compute the closure of this item set using the grammar's production rules.
    public func closure(
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> ItemSet {
        var result = self.items
        var worklist = Array(self.items)

        guard result.count <= limits.maxItemsPerState else {
            throw .resourceLimitExceeded(
                "Parser state exceeded item limit (\(result.count) items, limit \(limits.maxItemsPerState))"
            )
        }

        while let item = worklist.popLast() {
            let prod = productions[item.ruleIndex]
            guard item.dotPosition < prod.symbols.count else { continue }

            let symbolAfterDot = prod.symbols[item.dotPosition]
            guard let ruleIndices = rulesByNonTerminal[symbolAfterDot] else { continue }

            // Compute lookaheads: FIRST(β a) where β = symbols after dot+1, a = item.lookahead
            let betaSymbols = Array(prod.symbols.dropFirst(item.dotPosition + 1))
            let lookaheads = computeFirst(
                symbols: betaSymbols, fallback: item.lookahead, firstSets: firstSets)

            for ruleIdx in ruleIndices {
                for la in lookaheads {
                    let newItem = LRItem(ruleIndex: ruleIdx, dotPosition: 0, lookahead: la)
                    if result.insert(newItem).inserted {
                        guard result.count <= limits.maxItemsPerState else {
                            throw .resourceLimitExceeded(
                                "Parser state exceeded item limit (\(result.count) items, limit \(limits.maxItemsPerState))"
                            )
                        }
                        worklist.append(newItem)
                    }
                }
            }
        }

        return ItemSet(items: result)
    }

    /// Compute the GOTO set: advance dot past `symbol`.
    public func goto(
        symbol: String,
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> ItemSet {
        var kernel = Set<LRItem>()
        for item in items {
            let prod = productions[item.ruleIndex]
            guard item.dotPosition < prod.symbols.count else { continue }
            if prod.symbols[item.dotPosition] == symbol {
                kernel.insert(
                    LRItem(
                        ruleIndex: item.ruleIndex,
                        dotPosition: item.dotPosition + 1,
                        lookahead: item.lookahead
                    ))
            }
        }
        return try ItemSet(items: kernel).closure(
            productions: productions,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNonTerminal,
            limits: limits
        )
    }

    private func computeFirst(
        symbols: [String],
        fallback: String,
        firstSets: [String: Set<String>]
    ) -> Set<String> {
        var result = Set<String>()
        var canDerive = true

        for sym in symbols {
            guard canDerive else { break }
            if let firsts = firstSets[sym] {
                result.formUnion(firsts.filter { $0 != "" })
                if !firsts.contains("") {
                    canDerive = false
                }
            } else {
                // Terminal
                result.insert(sym)
                canDerive = false
            }
        }

        if canDerive {
            result.insert(fallback)
        }

        return result
    }
}
