struct FlatProduction: Sendable, Equatable {
    var name: String
    var symbols: [String]
    var fields: [Int: String]
}

private struct FlatSequence: Sendable, Equatable {
    var symbols: [String]
    var fields: [Int: String]

    static let empty = FlatSequence(symbols: [], fields: [:])
}

private struct FlattenContext: Sendable {
    var auxiliaryProductions: [FlatProduction] = []
    var counter = 0

    mutating func freshName(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)_\(counter)"
    }
}

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
    public struct CompilationResult: Sendable, Codable {
        public var parseTable: ParseTable
        public var lexTable: LexTable
        public var productions: [ProductionRule]
    }

    /// Compile a grammar definition into parse tables.
    public static func compile(_ grammar: GrammarDefinition) throws(GrammarError) -> CompilationResult {
        let flattened = flattenRules(grammar)
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
        let (itemSets, transitions) = buildItemSets(
            productions: grammarProductions,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNT,
            allSymbols: allSymbols
        )

        // Build parse table
        let table = buildParseTable(
            itemSets: itemSets,
            transitions: transitions,
            productions: grammarProductions,
            terminals: terminals,
            nonTerminals: nonTerminals
        )

        let productions = flattened.map { prod in
            ProductionRule(
                name: prod.name,
                symbolCount: prod.symbols.count,
                symbols: prod.symbols,
                fields: prod.fields
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

    private static func flattenRules(_ grammar: GrammarDefinition) -> [FlatProduction] {
        var productions: [FlatProduction] = []
        var context = FlattenContext()

        // Add augmented start rule: S' → startSymbol
        if let first = grammar.rules.first {
            productions.append(FlatProduction(name: "_start", symbols: [first.name], fields: [:]))
        }

        for (name, rule) in grammar.rules {
            let expanded = expandRule(rule, context: &context)
            for production in expanded {
                productions.append(FlatProduction(
                    name: name,
                    symbols: production.symbols,
                    fields: production.fields
                ))
            }
        }

        productions.append(contentsOf: context.auxiliaryProductions)
        return productions
    }

    private static func expandRule(_ rule: Rule, context: inout FlattenContext) -> [FlatSequence] {
        switch rule {
        case .symbol(let name):
            return [FlatSequence(symbols: [name], fields: [:])]
        case .string(let value):
            return [FlatSequence(symbols: ["\"" + value + "\""], fields: [:])]
        case .pattern:
            // Patterns become terminal tokens — use a placeholder
            return [FlatSequence(symbols: ["_pattern"], fields: [:])]
        case .seq(let members):
            var result = [FlatSequence.empty]
            for member in members {
                let memberExpanded = expandRule(member, context: &context)
                var newResult: [FlatSequence] = []
                for existing in result {
                    for expanded in memberExpanded {
                        newResult.append(combine(existing, expanded))
                    }
                }
                result = newResult
            }
            return result
        case .choice(let members):
            var productions: [FlatSequence] = []
            for member in members {
                productions.append(contentsOf: expandRule(member, context: &context))
            }
            return productions
        case .repeat(let content):
            let helperName = context.freshName("_repeat")
            let inner = expandRule(content, context: &context)
            let recursiveAlternatives = inner.filter { !$0.symbols.isEmpty }

            context.auxiliaryProductions.append(FlatProduction(name: helperName, symbols: [], fields: [:]))
            for alternative in recursiveAlternatives {
                context.auxiliaryProductions.append(FlatProduction(
                    name: helperName,
                    symbols: [helperName] + alternative.symbols,
                    fields: shiftFields(alternative.fields, by: 1)
                ))
            }

            return [FlatSequence(symbols: [helperName], fields: [:])]
        case .repeat1(let content):
            let helperName = context.freshName("_repeat1")
            let inner = expandRule(content, context: &context)
            let recursiveAlternatives = inner.filter { !$0.symbols.isEmpty }

            for alternative in inner {
                context.auxiliaryProductions.append(FlatProduction(
                    name: helperName,
                    symbols: alternative.symbols,
                    fields: alternative.fields
                ))
            }
            for alternative in recursiveAlternatives {
                context.auxiliaryProductions.append(FlatProduction(
                    name: helperName,
                    symbols: [helperName] + alternative.symbols,
                    fields: shiftFields(alternative.fields, by: 1)
                ))
            }

            return [FlatSequence(symbols: [helperName], fields: [:])]
        case .optional(let content):
            return [FlatSequence.empty] + expandRule(content, context: &context)
        case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content),
             .precDynamic(_, let content):
            return expandRule(content, context: &context)
        case .token(let content), .immediateToken(let content):
            return expandRule(content, context: &context)
        case .field(let name, let content):
            return expandRule(content, context: &context).map { production in
                guard !production.symbols.isEmpty else {
                    return production
                }

                var fields = production.fields
                fields[0] = name
                return FlatSequence(symbols: production.symbols, fields: fields)
            }
        case .alias(let content, _, _):
            return expandRule(content, context: &context)
        case .blank:
            return [FlatSequence.empty]
        }
    }

    private static func combine(_ lhs: FlatSequence, _ rhs: FlatSequence) -> FlatSequence {
        var fields = lhs.fields
        for (index, name) in rhs.fields {
            fields[lhs.symbols.count + index] = name
        }

        return FlatSequence(symbols: lhs.symbols + rhs.symbols, fields: fields)
    }

    private static func shiftFields(_ fields: [Int: String], by offset: Int) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: fields.map { (index, name) in
            (index + offset, name)
        })
    }

    private static func collectTerminals(
        _ productions: [FlatProduction],
        nonTerminals: Set<String>
    ) -> [String] {
        var terminals = Set<String>()
        for prod in productions {
            for sym in prod.symbols {
                if !nonTerminals.contains(sym) {
                    terminals.insert(sym)
                }
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
                    if let firsts = firstSets[sym] {
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
                    } else {
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
