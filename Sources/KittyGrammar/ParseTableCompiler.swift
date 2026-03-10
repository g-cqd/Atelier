/// Compiles a GrammarDefinition into an LR parse table.
///
/// This is a simplified LR(1) table compiler that:
/// 1. Flattens grammar rules into productions
/// 2. Computes FIRST sets
/// 3. Builds LR(1) item sets (states)
/// 4. Fills action/goto tables
/// 5. Marks unresolvable conflicts for GLR handling
public enum ParseTableCompiler: Sendable {

    /// Compiled result containing parse table, lex table, and production rules.
    public struct CompilationResult: Sendable {
        public var parseTable: ParseTable
        public var lexTable: LexTable
        public var productions: [ProductionRule]
    }

    /// Compile a grammar definition into parse tables.
    public static func compile(_ grammar: GrammarDefinition) throws(GrammarError) -> CompilationResult {
        let flattened = flattenRules(grammar)
        let terminals = collectTerminals(flattened, grammar: grammar)
        let nonTerminals = collectNonTerminals(flattened)
        let allSymbols = terminals + nonTerminals

        let firstSets = computeFirstSets(
            productions: flattened,
            terminals: Set(terminals),
            nonTerminals: Set(nonTerminals)
        )

        let rulesByNT = buildRuleIndex(flattened, nonTerminals: Set(nonTerminals))

        // Build item sets
        let (itemSets, transitions) = buildItemSets(
            productions: flattened,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNT,
            allSymbols: allSymbols
        )

        // Build parse table
        let table = buildParseTable(
            itemSets: itemSets,
            transitions: transitions,
            productions: flattened,
            terminals: terminals,
            nonTerminals: nonTerminals
        )

        let productions = flattened.map { prod in
            ProductionRule(name: prod.name, symbolCount: prod.symbols.count, symbols: prod.symbols)
        }

        let lexTable = LexTableCompiler.compile(grammar)

        return CompilationResult(
            parseTable: table,
            lexTable: lexTable,
            productions: productions
        )
    }

    // MARK: - Private

    private static func flattenRules(_ grammar: GrammarDefinition) -> [(name: String, symbols: [String])] {
        var productions: [(name: String, symbols: [String])] = []

        // Add augmented start rule: S' → startSymbol
        if let first = grammar.rules.first {
            productions.append((name: "_start", symbols: [first.name]))
        }

        for (name, rule) in grammar.rules {
            let expanded = expandRule(rule)
            for symbols in expanded {
                productions.append((name: name, symbols: symbols))
            }
        }

        return productions
    }

    private static func expandRule(_ rule: Rule) -> [[String]] {
        switch rule {
        case .symbol(let name):
            return [[name]]
        case .string(let value):
            return [["\"" + value + "\""]]
        case .pattern:
            // Patterns become terminal tokens — use a placeholder
            return [["_pattern"]]
        case .seq(let members):
            var result: [[String]] = [[]]
            for member in members {
                let memberExpanded = expandRule(member)
                var newResult: [[String]] = []
                for existing in result {
                    for expanded in memberExpanded {
                        newResult.append(existing + expanded)
                    }
                }
                result = newResult
            }
            return result
        case .choice(let members):
            return members.flatMap { expandRule($0) }
        case .repeat(let content):
            // A* → ε | A* A
            let inner = expandRule(content)
            // Simplified: just produce empty and single occurrence
            return [[]] + inner
        case .repeat1(let content):
            return expandRule(content)
        case .optional(let content):
            return [[]] + expandRule(content)
        case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content),
             .precDynamic(_, let content):
            return expandRule(content)
        case .token(let content), .immediateToken(let content):
            return expandRule(content)
        case .field(_, let content):
            return expandRule(content)
        case .alias(let content, _, _):
            return expandRule(content)
        case .blank:
            return [[]]
        }
    }

    private static func collectTerminals(
        _ productions: [(name: String, symbols: [String])],
        grammar: GrammarDefinition
    ) -> [String] {
        let ntNames = Set(grammar.rules.map(\.name) + ["_start"])
        var terminals = Set<String>()
        for prod in productions {
            for sym in prod.symbols {
                if !ntNames.contains(sym) {
                    terminals.insert(sym)
                }
            }
        }
        terminals.insert("$end")
        return terminals.sorted()
    }

    private static func collectNonTerminals(_ productions: [(name: String, symbols: [String])]) -> [String] {
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
                    if let firsts = firstSets[sym] {
                        let nonEmpty = firsts.filter { $0 != "" }
                        let before = firstSets[prod.name]!.count
                        firstSets[prod.name]!.formUnion(nonEmpty)
                        if firstSets[prod.name]!.count > before { changed = true }
                        if !firsts.contains("") {
                            canDerive = false
                            break
                        }
                    } else {
                        canDerive = false
                        break
                    }
                }
                if canDerive || prod.symbols.isEmpty {
                    if firstSets[prod.name]!.insert("").inserted {
                        changed = true
                    }
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
        for (i, prod) in productions.enumerated() {
            if nonTerminals.contains(prod.name) {
                index[prod.name, default: []].append(i)
            }
        }
        return index
    }

    private static func buildItemSets(
        productions: [(name: String, symbols: [String])],
        firstSets: [String: Set<String>],
        rulesByNonTerminal: [String: [Int]],
        allSymbols: [String]
    ) -> ([ItemSet], [Int: [(symbol: String, target: Int)]]) {
        // Initial item: S' → . startSymbol, $end
        let startItem = LRItem(ruleIndex: 0, dotPosition: 0, lookahead: "$end")
        let startSet = ItemSet(items: [startItem]).closure(
            productions: productions, firstSets: firstSets, rulesByNonTerminal: rulesByNonTerminal
        )

        var itemSets = [startSet]
        var setIndex: [ItemSet: Int] = [startSet: 0]
        var transitions: [Int: [(symbol: String, target: Int)]] = [:]
        var worklist = [0]

        while let stateIdx = worklist.popLast() {
            let state = itemSets[stateIdx]

            for symbol in allSymbols {
                let gotoSet = state.goto(
                    symbol: symbol,
                    productions: productions,
                    firstSets: firstSets,
                    rulesByNonTerminal: rulesByNonTerminal
                )
                guard !gotoSet.items.isEmpty else { continue }

                let targetIdx: Int
                if let existing = setIndex[gotoSet] {
                    targetIdx = existing
                } else {
                    targetIdx = itemSets.count
                    itemSets.append(gotoSet)
                    setIndex[gotoSet] = targetIdx
                    worklist.append(targetIdx)
                }
                transitions[stateIdx, default: []].append((symbol: symbol, target: targetIdx))
            }
        }

        return (itemSets, transitions)
    }

    private static func buildParseTable(
        itemSets: [ItemSet],
        transitions: [Int: [(symbol: String, target: Int)]],
        productions: [(name: String, symbols: [String])],
        terminals: [String],
        nonTerminals: [String]
    ) -> ParseTable {
        let terminalIndex = Dictionary(uniqueKeysWithValues: terminals.enumerated().map { ($1, $0) })
        let ntIndex = Dictionary(uniqueKeysWithValues: nonTerminals.enumerated().map { ($1, $0) })

        var actions = [[Action]](repeating: [Action](repeating: .error, count: terminals.count), count: itemSets.count)
        var gotos = [[Int?]](repeating: [Int?](repeating: nil, count: nonTerminals.count), count: itemSets.count)

        for (stateIdx, itemSet) in itemSets.enumerated() {
            // Fill from transitions (shifts and gotos)
            if let trans = transitions[stateIdx] {
                for (symbol, target) in trans {
                    if let tIdx = terminalIndex[symbol] {
                        let newAction = Action.shift(target)
                        actions[stateIdx][tIdx] = resolveConflict(existing: actions[stateIdx][tIdx], new: newAction)
                    } else if let ntIdx = ntIndex[symbol] {
                        gotos[stateIdx][ntIdx] = target
                    }
                }
            }

            // Fill reduces from completed items
            for item in itemSet.items {
                let prod = productions[item.ruleIndex]
                guard item.dotPosition == prod.symbols.count else { continue }

                if item.ruleIndex == 0 {
                    // Accept
                    if let tIdx = terminalIndex["$end"] {
                        actions[stateIdx][tIdx] = .accept
                    }
                } else {
                    if let tIdx = terminalIndex[item.lookahead] {
                        let newAction = Action.reduce(
                            ruleIndex: item.ruleIndex,
                            count: prod.symbols.count,
                            nonTerminal: prod.name
                        )
                        actions[stateIdx][tIdx] = resolveConflict(existing: actions[stateIdx][tIdx], new: newAction)
                    }
                }
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

    private static func resolveConflict(existing: Action, new: Action) -> Action {
        switch existing {
        case .error:
            return new
        case .accept:
            return existing
        case .shift, .reduce:
            if existing == new { return existing }
            // Unresolvable conflict — mark for GLR
            return .conflict([existing, new])
        case .conflict(var actions):
            if !actions.contains(new) {
                actions.append(new)
            }
            return .conflict(actions)
        }
    }
}
