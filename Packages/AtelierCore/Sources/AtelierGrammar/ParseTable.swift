// MARK: - Parse Table

/// An LR parse table: 2D array of actions indexed by (state, symbol).
public struct ParseTable: Sendable, Equatable, Codable {
    public var stateCount: Int
    public var symbols: [String]
    public var terminals: [String]
    public var nonTerminals: [String]
    public var actions: [[Action]]  // [state][symbolIndex] → Action
    public var gotos: [[Int?]]  // [state][nonTerminalIndex] → state or nil
    /// External symbol names in the grammar's declared order.
    public var externalNames: [String]
    /// The parse-table terminal for each external, including quoted literal terminal names.
    public var externalSymbols: [String]
    /// The external scanner's validity array for each parse state, in ``externalNames`` order.
    public var validExternals: [[Bool]]
    /// External symbols that the grammar treats as extras in every state.
    public var externalIsExtra: [Bool]
    /// The shifts precedence resolved against in favour of a reduction, by state then terminal: their target states.
    ///
    /// The compiler merges LR(1) states that share a core, so a state may reduce on a lookahead that only another
    /// context it stands for can follow the reduction with; a shift that precedence set against that reduction is then
    /// lost to a context that needed it, where tree-sitter's state, holding one context, has no conflict at all. Such a
    /// reduction cannot end in a shift of the lookahead, so a parser whose stack cannot shift it after the reduction
    /// takes the shift instead.
    public var lostShifts: [Int: [Int: Int]]

    public init(
        stateCount: Int,
        symbols: [String],
        terminals: [String],
        nonTerminals: [String],
        actions: [[Action]],
        gotos: [[Int?]],
        externalNames: [String] = [],
        externalSymbols: [String] = [],
        validExternals: [[Bool]] = [],
        externalIsExtra: [Bool] = [],
        lostShifts: [Int: [Int: Int]] = [:]
    ) {
        self.stateCount = stateCount
        self.symbols = symbols
        self.terminals = terminals
        self.nonTerminals = nonTerminals
        self.actions = actions
        self.gotos = gotos
        self.externalNames = externalNames
        self.externalSymbols = externalSymbols
        self.validExternals = validExternals
        self.externalIsExtra = externalIsExtra
        self.lostShifts = lostShifts
    }

    private enum CodingKeys: String, CodingKey {
        case stateCount, symbols, terminals, nonTerminals, actions, gotos, externalNames, externalSymbols
        case validExternals, externalIsExtra, lostShifts
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stateCount = try values.decode(Int.self, forKey: .stateCount)
        symbols = try values.decode([String].self, forKey: .symbols)
        terminals = try values.decode([String].self, forKey: .terminals)
        nonTerminals = try values.decode([String].self, forKey: .nonTerminals)
        actions = try values.decode([[Action]].self, forKey: .actions)
        gotos = try values.decode([[Int?]].self, forKey: .gotos)
        externalNames = try values.decodeIfPresent([String].self, forKey: .externalNames) ?? []
        externalSymbols = try values.decodeIfPresent([String].self, forKey: .externalSymbols) ?? externalNames
        validExternals = try values.decodeIfPresent([[Bool]].self, forKey: .validExternals) ?? []
        externalIsExtra = try values.decodeIfPresent([Bool].self, forKey: .externalIsExtra) ?? []
        lostShifts = try values.decodeIfPresent([Int: [Int: Int]].self, forKey: .lostShifts) ?? [:]
    }
}

// MARK: - Action

public enum Action: Sendable, Equatable, Codable {
    case shift(Int)  // Shift and go to state
    case reduce(ruleIndex: Int, count: Int, nonTerminal: String)  // Reduce
    case accept
    case error
    case conflict([Action])  // GLR conflict — fork the parser

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case ruleIndex
        case count
        case nonTerminal
        case actions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
            case "shift":
                self = .shift(try container.decode(Int.self, forKey: .state))
            case "reduce":
                self = .reduce(
                    ruleIndex: try container.decode(Int.self, forKey: .ruleIndex),
                    count: try container.decode(Int.self, forKey: .count),
                    nonTerminal: try container.decode(String.self, forKey: .nonTerminal)
                )
            case "accept":
                self = .accept
            case "error":
                self = .error
            case "conflict":
                self = .conflict(try container.decode([Action].self, forKey: .actions))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown Action type: \(type)"
                )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .shift(let state):
                try container.encode("shift", forKey: .type)
                try container.encode(state, forKey: .state)
            case .reduce(let ruleIndex, let count, let nonTerminal):
                try container.encode("reduce", forKey: .type)
                try container.encode(ruleIndex, forKey: .ruleIndex)
                try container.encode(count, forKey: .count)
                try container.encode(nonTerminal, forKey: .nonTerminal)
            case .accept:
                try container.encode("accept", forKey: .type)
            case .error:
                try container.encode("error", forKey: .type)
            case .conflict(let actions):
                try container.encode("conflict", forKey: .type)
                try container.encode(actions, forKey: .actions)
        }
    }
}

// MARK: - Comment Pattern

/// Describes how comments look in a language, extracted from grammar extras.
public enum CommentPattern: Sendable, Equatable {
    case line(prefix: String)  // e.g. "//" → scan to end of line
    case block(open: String, close: String)  // e.g. "/*" … "*/"

    private enum CodingKeys: String, CodingKey {
        case kind, prefix, open, close
    }
}

extension CommentPattern: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
            case "line":
                self = .line(prefix: try c.decode(String.self, forKey: .prefix))
            case "block":
                self = .block(
                    open: try c.decode(String.self, forKey: .open),
                    close: try c.decode(String.self, forKey: .close)
                )
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c, debugDescription: "Unknown CommentPattern kind: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .line(let prefix):
                try c.encode("line", forKey: .kind)
                try c.encode(prefix, forKey: .prefix)
            case .block(let open, let close):
                try c.encode("block", forKey: .kind)
                try c.encode(open, forKey: .open)
                try c.encode(close, forKey: .close)
        }
    }
}

// MARK: - Lex Table

/// A lexer's tables. A compiled grammar lexes with ``automaton``, one token at a time, in the lex mode of the parse
/// state it is in; a table without lex modes, as tests build by hand, lexes context-free with the keyword trie in
/// ``states`` and ``commentPatterns``.
public struct LexTable: Sendable, Equatable, Codable {
    public var states: [LexState]
    public var keywords: [String: Int]  // keyword string → token ID
    public var commentPatterns: [CommentPattern]
    /// The tokens ``automaton`` accepts, by index.
    public var tokens: [LexToken]
    /// The lexer's automaton over Unicode scalars, which every lex mode shares.
    public var automaton: [LexAutomatonState]
    /// Each lex mode's start state in ``automaton``: a mode reads only the tokens valid in the parse states that use
    /// it, so a token is read as the parser expects it.
    public var modeStarts: [Int]
    /// The lex mode of each parse state.
    public var stateModes: [Int]
    /// The mode to read a token in when no stack's mode reads one: every token that may follow a separator, but those
    /// that may start as a separator does.
    public var errorMode: Int?
    /// The lexical token designated by the grammar's `word` field, if any.
    public var wordToken: Int?
    /// Literal keywords that the word token can also match, keyed by spelling.
    public var keywordTokens: [String: Int]
    /// Token indices enabled in each lexical mode, for contextual keyword classification.
    public var modeValidTokens: [[Int]]
    /// The preferred nullable token in each mode, used only if no nonempty token matches.
    public var modeEmptyTokens: [Int?]
    /// The preferred nullable token after a separator, excluding immediate tokens.
    public var modeEmptyAfterSeparator: [Int?]
    /// The tokens' automaton, for ``mode(reading:)`` to build a mode no parse state has; nil for a table built by
    /// hand.
    var modeSource: LexModeSource?

    public init(
        states: [LexState] = [], keywords: [String: Int] = [:],
        commentPatterns: [CommentPattern] = [],
        tokens: [LexToken] = [],
        automaton: [LexAutomatonState] = [],
        modeStarts: [Int] = [],
        stateModes: [Int] = [],
        errorMode: Int? = nil,
        wordToken: Int? = nil,
        keywordTokens: [String: Int] = [:],
        modeValidTokens: [[Int]] = [],
        modeEmptyTokens: [Int?] = [],
        modeEmptyAfterSeparator: [Int?] = []
    ) {
        self.init(
            states: states, keywords: keywords, commentPatterns: commentPatterns, tokens: tokens, automaton: automaton,
            modeStarts: modeStarts, stateModes: stateModes, errorMode: errorMode, wordToken: wordToken,
            keywordTokens: keywordTokens, modeValidTokens: modeValidTokens, modeEmptyTokens: modeEmptyTokens,
            modeEmptyAfterSeparator: modeEmptyAfterSeparator, modeSource: nil)
    }

    init(
        states: [LexState] = [], keywords: [String: Int] = [:],
        commentPatterns: [CommentPattern] = [],
        tokens: [LexToken] = [],
        automaton: [LexAutomatonState] = [],
        modeStarts: [Int] = [],
        stateModes: [Int] = [],
        errorMode: Int? = nil,
        wordToken: Int? = nil,
        keywordTokens: [String: Int] = [:],
        modeValidTokens: [[Int]] = [],
        modeEmptyTokens: [Int?] = [],
        modeEmptyAfterSeparator: [Int?] = [],
        modeSource: LexModeSource?
    ) {
        self.states = states
        self.keywords = keywords
        self.commentPatterns = commentPatterns
        self.tokens = tokens
        self.automaton = automaton
        self.modeStarts = modeStarts
        self.stateModes = stateModes
        self.errorMode = errorMode
        self.wordToken = wordToken
        self.keywordTokens = keywordTokens
        self.modeValidTokens = modeValidTokens
        self.modeEmptyTokens = modeEmptyTokens
        self.modeEmptyAfterSeparator = modeEmptyAfterSeparator
        self.modeSource = modeSource
    }

    /// A lex mode reading exactly the tokens `validTokens` lists, built from the tokens' automaton as reads reach its
    /// states: for a parser whose stack can take only some of the tokens its state's mode reads. Nil for a table
    /// without the automaton, as one built by hand, or for an index outside ``tokens``.
    /// - Throws: `GrammarError.resourceLimitExceeded` when the mode's automaton passes its limit.
    public func lazyMode(reading validTokens: [Int]) throws(GrammarError) -> LazyLexMode? {
        guard let modeSource, validTokens.allSatisfy(tokens.indices.contains) else { return nil }
        return try LazyLexMode(source: modeSource, validTokens: validTokens)
    }
}

/// A lex mode for some of a table's tokens whose automaton states are built the first time a read reaches them, so a
/// mode read a few times costs the states those reads pass through rather than every state the mode could reach.
public struct LazyLexMode: Sendable {
    private var builder: LexAutomatonBuilder
    /// The start state.
    public let start: Int
    /// The tokens the mode reads, sorted.
    public let validTokens: [Int]
    /// The preferred token of the mode that matches the empty string, read where no other token matches.
    public let emptyToken: Int?
    /// The same, after a separator: immediate tokens left out.
    public let emptyTokenAfterSeparator: Int?

    init(source: LexModeSource, validTokens: [Int]) throws(GrammarError) {
        builder = LexAutomatonBuilder(nfa: source.nfa, tokens: source.priorities)
        start = try builder.lazyStartState(for: validTokens)
        self.validTokens = validTokens.sorted()
        emptyToken = LexTableCompiler.preferredEmptyToken(
            in: validTokens, nfa: source.nfa, tokens: source.priorities, afterSeparator: false)
        emptyTokenAfterSeparator = LexTableCompiler.preferredEmptyToken(
            in: validTokens, nfa: source.nfa, tokens: source.priorities, afterSeparator: true)
    }

    /// State `id` with its accepted token and moves, built now if no read reached it before.
    /// - Throws: `GrammarError.resourceLimitExceeded` when the automaton passes its limit.
    public mutating func state(_ id: Int) throws(GrammarError) -> LexAutomatonState {
        try builder.populated(id)
    }
}

/// What building a lex mode takes besides the table's tokens: their automaton, and how each ranks against the others.
struct LexModeSource: Sendable, Equatable, Codable {
    var nfa: TokenNFA
    var priorities: [LexTokenPriority]
}

/// A single DFA state for lexing.
public struct LexState: Sendable, Equatable, Codable {
    public var transitions: [(ClosedRange<UInt32>, Int)]  // character range → next state
    public var accepting: Int?  // token ID if this is an accepting state

    public init(transitions: [(ClosedRange<UInt32>, Int)] = [], accepting: Int? = nil) {
        self.transitions = transitions
        self.accepting = accepting
    }

    public static func == (lhs: LexState, rhs: LexState) -> Bool {
        lhs.accepting == rhs.accepting && lhs.transitions.count == rhs.transitions.count
            && zip(lhs.transitions, rhs.transitions).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case transitions
        case accepting
    }

    private struct TransitionEntry: Codable {
        var lower: UInt32
        var upper: UInt32
        var target: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([TransitionEntry].self, forKey: .transitions)
        // A range is only built from ordered bounds: a damaged cache file must fail to decode, not trap.
        guard entries.allSatisfy({ $0.lower <= $0.upper }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .transitions, in: container, debugDescription: "A transition's lower bound exceeds its upper")
        }
        self.transitions = entries.map { ($0.lower ... $0.upper, $0.target) }
        self.accepting = try container.decodeIfPresent(Int.self, forKey: .accepting)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = transitions.map {
            TransitionEntry(lower: $0.0.lowerBound, upper: $0.0.upperBound, target: $0.1)
        }
        try container.encode(entries, forKey: .transitions)
        try container.encodeIfPresent(accepting, forKey: .accepting)
    }
}

// MARK: - Production Rule

/// The name a production gives the node at one of its steps in place of the node's own: tree-sitter's `alias`.
public struct SymbolAlias: Sendable, Equatable, Codable {
    /// The node's type: the alias for a named alias, and for an anonymous one the alias in quotes, as the type of an
    /// anonymous token is.
    public var type: String
    public var isNamed: Bool

    public init(type: String, isNamed: Bool) {
        self.type = type
        self.isNamed = isNamed
    }
}

public struct ProductionRule: Sendable, Equatable, Codable {
    public var name: String
    public var symbolCount: Int
    public var symbols: [String]
    public var fields: [Int: String]
    /// The aliases of the production's steps, by step index.
    public var aliases: [Int: SymbolAlias]
    /// The production's `prec.dynamic` value: of two parses that tie on errors, the one whose reductions add up to
    /// more wins.
    public var dynamicPrecedence: Int

    public init(
        name: String,
        symbolCount: Int,
        symbols: [String] = [],
        fields: [Int: String] = [:],
        aliases: [Int: SymbolAlias] = [:],
        dynamicPrecedence: Int = 0
    ) {
        self.name = name
        self.symbolCount = symbolCount
        self.symbols = symbols
        self.fields = fields
        self.aliases = aliases
        self.dynamicPrecedence = dynamicPrecedence
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name
        case symbolCount
        case symbols
        case fields
        case aliases
        case dynamicPrecedence
    }

    /// An entry of `aliases` as the cache stores it.
    private struct IndexedAlias: Codable {
        var index: Int
        var alias: SymbolAlias
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.symbolCount = try container.decode(Int.self, forKey: .symbolCount)
        self.symbols = try container.decode([String].self, forKey: .symbols)
        let pairs = try container.decode([[String]].self, forKey: .fields)
        var decoded: [Int: String] = [:]
        for pair in pairs {
            guard pair.count == 2, let index = Int(pair[0]) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fields,
                    in: container,
                    debugDescription: "Expected [index, name] pair"
                )
            }
            decoded[index] = pair[1]
        }
        self.fields = decoded
        let aliases = try container.decodeIfPresent([IndexedAlias].self, forKey: .aliases) ?? []
        self.aliases = Dictionary(aliases.map { ($0.index, $0.alias) }, uniquingKeysWith: { first, _ in first })
        self.dynamicPrecedence = try container.decodeIfPresent(Int.self, forKey: .dynamicPrecedence) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(symbolCount, forKey: .symbolCount)
        try container.encode(symbols, forKey: .symbols)
        let pairs = fields.sorted(by: { $0.key < $1.key }).map { [String($0.key), $0.value] }
        try container.encode(pairs, forKey: .fields)
        let aliases = self.aliases.sorted(by: { $0.key < $1.key }).map { IndexedAlias(index: $0.key, alias: $0.value) }
        try container.encode(aliases, forKey: .aliases)
        try container.encode(dynamicPrecedence, forKey: .dynamicPrecedence)
    }
}
