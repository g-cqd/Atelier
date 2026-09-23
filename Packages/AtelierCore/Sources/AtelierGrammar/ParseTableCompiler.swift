public struct GrammarCompilationLimits: Sendable, Equatable {
    public var maxExpandedAlternativesPerRule: Int
    public var maxFlattenedProductions: Int
    public var maxProductionSymbols: Int
    public var maxItemsPerState: Int
    public var maxStates: Int
    public var maxTransitions: Int

    public init(
        maxExpandedAlternativesPerRule: Int = 4_096,
        maxFlattenedProductions: Int = 50_000,
        maxProductionSymbols: Int = 200_000,
        maxItemsPerState: Int = 20_000,
        maxStates: Int = 4_000,
        maxTransitions: Int = 200_000
    ) {
        self.maxExpandedAlternativesPerRule = maxExpandedAlternativesPerRule
        self.maxFlattenedProductions = maxFlattenedProductions
        self.maxProductionSymbols = maxProductionSymbols
        self.maxItemsPerState = maxItemsPerState
        self.maxStates = maxStates
        self.maxTransitions = maxTransitions
    }

    public static let `default` = GrammarCompilationLimits()
}

/// Compiles a GrammarDefinition into an LR parse table.
///
/// A canonical LR(1) compiler that:
/// 1. Flattens grammar rules into productions, keeping the precedence and associativity of each step
/// 2. Computes FIRST sets
/// 3. Builds LR(1) item sets (states)
/// 4. Fills action/goto tables, resolving shift/reduce conflicts by precedence and associativity as tree-sitter does
/// 5. Keeps the conflicts precedence can't resolve, for the GLR parser to fork on
public enum ParseTableCompiler: Sendable {
    /// Compiled result containing parse table, lex table, and production rules.
    public struct CompilationResult: Sendable, Codable {
        public var parseTable: ParseTable
        public var lexTable: LexTable
        public var productions: [ProductionRule]
    }

    /// The version of what ``compile(_:limits:)`` produces, for caches of compiled tables to key on: bumped whenever
    /// the tables compiled from the same grammar change, so no cache hands out tables an older compiler made.
    public static let formatVersion = 2

    /// Compile a grammar definition into parse tables.
    public static func compile(
        _ grammar: GrammarDefinition,
        limits: GrammarCompilationLimits = .default
    ) throws(GrammarError) -> CompilationResult {
        let flattened = try ProductionFlattener.flatten(grammar.rules, limits: limits)
        let nonTerminals = collectNonTerminals(flattened)
        let terminals = collectTerminals(flattened, nonTerminals: Set(nonTerminals))
        let grammarProductions = flattened.map { (name: $0.name, symbols: $0.symbols) }
        let allSymbols = terminals + nonTerminals

        let firstSets = computeFirstSets(
            productions: grammarProductions,
            terminals: Set(terminals),
            nonTerminals: Set(nonTerminals)
        )

        let rulesByNT = buildRuleIndex(grammarProductions, nonTerminals: Set(nonTerminals))

        // Build item sets
        let (itemSets, transitions) = try buildItemSets(
            productions: grammarProductions,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNT,
            allSymbols: allSymbols,
            limits: limits
        )

        let table = ParseActionResolver(productions: flattened, firstSets: firstSets)
            .parseTable(itemSets: itemSets, transitions: transitions, terminals: terminals, nonTerminals: nonTerminals)

        let productions = flattened.map { production in
            ProductionRule(
                name: production.name,
                symbolCount: production.steps.count,
                symbols: production.symbols,
                fields: production.fields
            )
        }

        let lexTable = LexTableCompiler.compile(grammar)

        return CompilationResult(
            parseTable: table,
            lexTable: lexTable,
            productions: productions
        )
    }

    // MARK: - Private

    private static func collectTerminals(
        _ productions: [FlatProduction],
        nonTerminals: Set<String>
    ) -> [String] {
        var terminals = Set<String>()
        for prod in productions {
            for step in prod.steps where !nonTerminals.contains(step.symbol) {
                terminals.insert(step.symbol)
            }
        }
        terminals.insert("$end")
        return terminals.sorted()
    }

    private static func collectNonTerminals(_ productions: [FlatProduction]) -> [String] {
        var nts = Set<String>()
        for prod in productions {
            nts.insert(prod.name)
        }
        return nts.sorted()
    }

    private static func computeFirstSets(
        productions: [(name: String, symbols: [String])],
        terminals: Set<String>,
        nonTerminals: Set<String>
    ) -> [String: Set<String>] {
        var firstSets: [String: Set<String>] = [:]
        for t in terminals { firstSets[t] = [t] }
        for nt in nonTerminals { firstSets[nt] = [] }

        var changed = true
        while changed {
            changed = false
            for prod in productions {
                var canDerive = true
                for sym in prod.symbols {
                    guard let firsts = firstSets[sym] else {
                        canDerive = false
                        break
                    }
                    let nonEmpty = firsts.filter { $0 != "" }
                    var prodSet = firstSets[prod.name, default: []]
                    let before = prodSet.count
                    prodSet.formUnion(nonEmpty)
                    if prodSet.count > before { changed = true }
                    firstSets[prod.name] = prodSet
                    if !firsts.contains("") {
                        canDerive = false
                        break
                    }
                }
                if canDerive || prod.symbols.isEmpty {
                    var prodSet = firstSets[prod.name, default: []]
                    if prodSet.insert("").inserted {
                        changed = true
                    }
                    firstSets[prod.name] = prodSet
                }
            }
        }
        return firstSets
    }

    private static func buildRuleIndex(
        _ productions: [(name: String, symbols: [String])],
        nonTerminals: Set<String>
    ) -> [String: [Int]] {
        var index: [String: [Int]] = [:]
        for (i, prod) in productions.enumerated() where nonTerminals.contains(prod.name) {
            index[prod.name, default: []].append(i)
        }
        return index
    }

    private static func buildItemSets(
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        allSymbols: [String],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> ([ItemSet], [Int: [(symbol: String, target: Int)]]) {
        // Initial item: S' → . startSymbol, $end
        let startItem = LRItem(ruleIndex: 0, dotPosition: 0, lookahead: "$end")
        let startSet = try ItemSet(items: [startItem])
            .closure(
                productions: productions,
                firstSets: firstSets,
                rulesByNonTerminal: rulesByNonTerminal,
                limits: limits
            )

        var itemSets = [startSet]
        var setIndex: [ItemSet: Int] = [startSet: 0]
        var transitions: [Int: [(symbol: String, target: Int)]] = [:]
        var worklist = [0]
        var transitionCount = 0

        while let stateIdx = worklist.popLast() {
            let state = itemSets[stateIdx]

            for symbol in allSymbols {
                let gotoSet = try state.goto(
                    symbol: symbol,
                    productions: productions,
                    firstSets: firstSets,
                    rulesByNonTerminal: rulesByNonTerminal,
                    limits: limits
                )
                guard !gotoSet.items.isEmpty else { continue }

                let targetIdx: Int
                if let existing = setIndex[gotoSet] {
                    targetIdx = existing
                } else {
                    targetIdx = itemSets.count
                    guard targetIdx < limits.maxStates else {
                        throw .resourceLimitExceeded(
                            "Parser state construction exceeded limit (\(targetIdx + 1) states, limit \(limits.maxStates))"
                        )
                    }
                    itemSets.append(gotoSet)
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

        return (itemSets, transitions)
    }
}
