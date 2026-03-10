// MARK: - Parse Table

/// An LR parse table: 2D array of actions indexed by (state, symbol).
public struct ParseTable: Sendable, Equatable {
    public var stateCount: Int
    public var symbols: [String]
    public var terminals: [String]
    public var nonTerminals: [String]
    public var actions: [[Action]]  // [state][symbolIndex] → Action
    public var gotos: [[Int?]]      // [state][nonTerminalIndex] → state or nil

    public init(
        stateCount: Int,
        symbols: [String],
        terminals: [String],
        nonTerminals: [String],
        actions: [[Action]],
        gotos: [[Int?]]
    ) {
        self.stateCount = stateCount
        self.symbols = symbols
        self.terminals = terminals
        self.nonTerminals = nonTerminals
        self.actions = actions
        self.gotos = gotos
    }
}

// MARK: - Action

public enum Action: Sendable, Equatable {
    case shift(Int)                     // Shift and go to state
    case reduce(ruleIndex: Int, count: Int, nonTerminal: String)  // Reduce
    case accept
    case error
    case conflict([Action])             // GLR conflict — fork the parser
}

// MARK: - Lex Table

/// DFA states for tokenization.
public struct LexTable: Sendable, Equatable {
    public var states: [LexState]
    public var keywords: [String: Int]  // keyword string → token ID

    public init(states: [LexState] = [], keywords: [String: Int] = [:]) {
        self.states = states
        self.keywords = keywords
    }
}

/// A single DFA state for lexing.
public struct LexState: Sendable, Equatable {
    public var transitions: [(ClosedRange<UInt32>, Int)]  // character range → next state
    public var accepting: Int?  // token ID if this is an accepting state

    public init(transitions: [(ClosedRange<UInt32>, Int)] = [], accepting: Int? = nil) {
        self.transitions = transitions
        self.accepting = accepting
    }

    public static func == (lhs: LexState, rhs: LexState) -> Bool {
        lhs.accepting == rhs.accepting &&
        lhs.transitions.count == rhs.transitions.count &&
        zip(lhs.transitions, rhs.transitions).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

// MARK: - Production Rule

public struct ProductionRule: Sendable, Equatable {
    public var name: String
    public var symbolCount: Int
    public var symbols: [String]
    public var fields: [Int: String]

    public init(
        name: String,
        symbolCount: Int,
        symbols: [String] = [],
        fields: [Int: String] = [:]
    ) {
        self.name = name
        self.symbolCount = symbolCount
        self.symbols = symbols
        self.fields = fields
    }
}
