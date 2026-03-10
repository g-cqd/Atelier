// MARK: - Parse Table

/// An LR parse table: 2D array of actions indexed by (state, symbol).
public struct ParseTable: Sendable, Equatable, Codable {
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

public enum Action: Sendable, Equatable, Codable {
    case shift(Int)                     // Shift and go to state
    case reduce(ruleIndex: Int, count: Int, nonTerminal: String)  // Reduce
    case accept
    case error
    case conflict([Action])             // GLR conflict — fork the parser

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

// MARK: - Lex Table

/// DFA states for tokenization.
public struct LexTable: Sendable, Equatable, Codable {
    public var states: [LexState]
    public var keywords: [String: Int]  // keyword string → token ID

    public init(states: [LexState] = [], keywords: [String: Int] = [:]) {
        self.states = states
        self.keywords = keywords
    }
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
        lhs.accepting == rhs.accepting &&
        lhs.transitions.count == rhs.transitions.count &&
        zip(lhs.transitions, rhs.transitions).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
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
        self.transitions = entries.map { ($0.lower...$0.upper, $0.target) }
        self.accepting = try container.decodeIfPresent(Int.self, forKey: .accepting)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entries = transitions.map { TransitionEntry(lower: $0.0.lowerBound, upper: $0.0.upperBound, target: $0.1) }
        try container.encode(entries, forKey: .transitions)
        try container.encodeIfPresent(accepting, forKey: .accepting)
    }
}

// MARK: - Production Rule

public struct ProductionRule: Sendable, Equatable, Codable {
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

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name
        case symbolCount
        case symbols
        case fields
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
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(symbolCount, forKey: .symbolCount)
        try container.encode(symbols, forKey: .symbols)
        let pairs = fields.sorted(by: { $0.key < $1.key }).map { [String($0.key), $0.value] }
        try container.encode(pairs, forKey: .fields)
    }
}
