/// Bounds on the work of compiling a grammar, so one too large for this compiler fails fast instead of grinding.
///
/// The defaults leave about twice the room the largest bundled grammars take, as big as tree-sitter's own tables for
/// them: Bash's 8,911 states (tree-sitter's: 7,571) and TypeScript's 8,876 (5,986), TypeScript's largest state at under
/// 4,000 production positions, and Kotlin's 345,000 actions and gotos.
public struct GrammarCompilationLimits: Sendable, Equatable {
    public var maxExpandedAlternativesPerRule: Int
    public var maxFlattenedProductions: Int
    public var maxProductionSymbols: Int
    /// The most distinct production positions a state may hold, before lookahead sets are attached.
    public var maxItemsPerState: Int
    public var maxStates: Int
    public var maxTransitions: Int
    /// The total number of LR(1) item and lookahead pairs after core merging.
    public var maxLookaheadItems: Int

    public init(
        maxExpandedAlternativesPerRule: Int = 4_096,
        maxFlattenedProductions: Int = 50_000,
        maxProductionSymbols: Int = 200_000,
        maxItemsPerState: Int = 8_000,
        maxStates: Int = 20_000,
        maxTransitions: Int = 1_000_000,
        maxLookaheadItems: Int = 50_000_000
    ) {
        self.maxExpandedAlternativesPerRule = maxExpandedAlternativesPerRule
        self.maxFlattenedProductions = maxFlattenedProductions
        self.maxProductionSymbols = maxProductionSymbols
        self.maxItemsPerState = maxItemsPerState
        self.maxStates = maxStates
        self.maxTransitions = maxTransitions
        self.maxLookaheadItems = maxLookaheadItems
    }

    public static let `default` = GrammarCompilationLimits()
}

/// Compiles a GrammarDefinition into an LR parse table.
///
/// A core-merged LR(1) compiler that:
/// 1. Splits the grammar into tokens and syntactic rules, as tree-sitter does
/// 2. Flattens the syntactic rules into productions, keeping the precedence and associativity of each step
/// 3. Computes FIRST sets
/// 4. Builds LR(0) cores, propagates lookaheads, and separates merges that create reduction conflicts
/// 5. Fills action/goto tables, resolving shift/reduce conflicts by precedence and associativity as tree-sitter does
/// 6. Keeps declared and unresolved conflicts for the GLR parser to fork on
/// 7. Builds the lexer's automaton, with a lex mode for the tokens valid in each state
public enum ParseTableCompiler: Sendable {
    /// Compiled result containing parse table, lex table, and production rules.
    public struct CompilationResult: Sendable, Codable {
        public var parseTable: ParseTable
        public var lexTable: LexTable
        public var productions: [ProductionRule]
    }

    /// The version of what ``compile(_:limits:)`` produces, for caches of compiled tables and of failed compiles to
    /// key on: bumped whenever the outcome of compiling the same grammar changes, tables or error, which a change to
    /// the default limits can do too, so no cache hands out what an older compiler made.
    public static let formatVersion = 18

    /// Compile a grammar definition into parse tables.
    public static func compile(
        _ grammar: GrammarDefinition,
        limits: GrammarCompilationLimits = .default
    ) throws(GrammarError) -> CompilationResult {
        try compile(grammar, limits: limits, onPhase: nil)
    }

    /// The compiler pipeline with optional phase checkpoints for opt-in profiling.
    static func compile(
        _ grammar: GrammarDefinition,
        limits: GrammarCompilationLimits,
        onPhase: ((String) -> Void)?
    ) throws(GrammarError) -> CompilationResult {
        let lexical = try LexicalGrammar(grammar)
        onPhase?("lexical grammar")
        // Reading every token's pattern first fails a grammar with a pattern the lexer can't read before the costly
        // LR construction.
        let tokenAutomaton = try TokenNFA(tokens: lexical.tokens, separators: lexical.separators)
        onPhase?("token NFA")
        let flattened = try ProductionFlattener.flatten(lexical.syntacticRules, limits: limits)
        onPhase?("production flattening")
        let nonTerminals = collectNonTerminals(flattened)
        let terminals = collectTerminals(flattened, nonTerminals: Set(nonTerminals))
        let grammarProductions = flattened.map { (name: $0.name, symbols: $0.symbols) }

        let firstSets = computeFirstSets(
            productions: grammarProductions,
            terminals: Set(terminals),
            nonTerminals: Set(nonTerminals)
        )

        let rulesByNT = buildRuleIndex(grammarProductions, nonTerminals: Set(nonTerminals))
        onPhase?("symbols and FIRST sets")

        // Build item sets
        let (states, transitions) = try CoreItemSetBuilder.build(
            productions: grammarProductions,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNT,
            limits: limits,
            onPhase: onPhase
        )
        onPhase?("LR item sets")

        var table = ParseActionResolver(
            productions: flattened, firstSets: firstSets, precedences: grammar.precedences
        )
        .parseTable(states: states, transitions: transitions, terminals: terminals, nonTerminals: nonTerminals)
        populateExternalSymbols(in: &table, grammar: grammar, lexical: lexical)
        onPhase?("parse actions")

        let productions = flattened.map { production in
            ProductionRule(
                name: production.name,
                symbolCount: production.steps.count,
                symbols: production.symbols,
                fields: production.fields,
                aliases: production.aliases,
                dynamicPrecedence: production.dynamicPrecedence
            )
        }

        let wordToken = grammar.word.flatMap { name in lexical.tokens.firstIndex { $0.name == name } }
        let keywordSpellings = Set(KeywordExtractor.extract(from: grammar).keys)
        var keywordTokens: [String: Int] = [:]
        if wordToken != nil {
            for (index, token) in lexical.tokens.enumerated() {
                if let spelling = literalText(of: token.rule), keywordSpellings.contains(spelling) {
                    keywordTokens[spelling] = index
                }
            }
        }
        onPhase?("productions and keywords")
        let lexTable = try LexTableCompiler.compile(
            nfa: tokenAutomaton, tokens: lexical.tokens, validTokens: validTokens(in: table, of: lexical.tokens),
            wordToken: wordToken, keywordTokens: keywordTokens)
        onPhase?("lex modes")

        return CompilationResult(
            parseTable: table,
            lexTable: lexTable,
            productions: productions
        )
    }

    // MARK: - Private

    /// The name the tables give each of `grammar`'s externals, in grammar order: a symbol's name, a string's text, or a
    /// pattern's source. A scanner declares the same names, and the parser checks them before calling it.
    static func externalNames(of grammar: GrammarDefinition) -> [String] {
        grammar.externals.enumerated()
            .map { index, rule in
                switch rule {
                    case .symbol(let name): name
                    case .string(let value): value
                    case .pattern(let value): value
                    default: "_external_\(index)"
                }
            }
    }

    /// Gives each external its terminal and per-state validity in grammar order.
    private static func populateExternalSymbols(
        in table: inout ParseTable, grammar: GrammarDefinition, lexical: LexicalGrammar
    ) {
        table.externalNames = externalNames(of: grammar)
        table.externalSymbols = grammar.externals.enumerated()
            .map { index, rule in
                switch rule {
                    case .symbol(let name): name
                    case .string(let value): "\"\(value)\""
                    case .pattern:
                        lexical.tokens.first(where: { $0.rule == rule })?.name ?? table.externalNames[index]
                    default: table.externalNames[index]
                }
            }
        let extraNames = Set(
            grammar.extras.compactMap { rule -> String? in
                switch rule {
                    case .symbol(let name): name
                    case .string(let value): "\"\(value)\""
                    default: nil
                }
            })
        table.externalIsExtra = table.externalSymbols.map { extraNames.contains($0) }
        let terminalIndex = Dictionary(uniqueKeysWithValues: table.terminals.enumerated().map { ($1, $0) })
        let actions = table.actions
        table.validExternals = ExternalValidity(
            rows: (0 ..< actions.stateCount)
                .map { state in
                    table.externalSymbols.enumerated()
                        .map { external, name in
                            if table.externalIsExtra[external] { return true }
                            guard let terminal = terminalIndex[name] else { return false }
                            return !actions.isError(state: state, terminal: terminal)
                        }
                })
    }

    private static func literalText(of rule: Rule) -> String? {
        switch rule {
            case .string(let value): value
            case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content),
                .token(let content), .immediateToken(let content):
                literalText(of: content)
            default: nil
        }
    }

    /// The tokens valid in each state of `table`, by index into `tokens`: those with an action there, and the extras,
    /// which are valid everywhere.
    private static func validTokens(in table: ParseTable, of tokens: [LexicalToken]) -> [[Int]] {
        let terminalIndex = Dictionary(uniqueKeysWithValues: table.terminals.enumerated().map { ($1, $0) })
        let extras = tokens.indices.filter { tokens[$0].isExtra }
        let shifted = tokens.indices.compactMap { token -> (token: Int, terminal: Int)? in
            guard !tokens[token].isExtra, let terminal = terminalIndex[tokens[token].name] else { return nil }
            return (token, terminal)
        }
        return (0 ..< table.actions.stateCount)
            .map { state in
                (extras + shifted.filter { !table.actions.isError(state: state, terminal: $0.terminal) }.map(\.token))
                    .sorted()
            }
    }

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
}
