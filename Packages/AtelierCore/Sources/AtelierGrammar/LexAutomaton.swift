/// A token the lexer produces.
public struct LexToken: Sendable, Equatable, Codable {
    /// The terminal's name in the parse table, and the type of the token's leaf node: a rule's name for a named
    /// token, the text in quotes for an anonymous one.
    public var name: String
    public var isNamed: Bool
    /// Whether the parser skips the token rather than shifting it, as it does comments and the grammar's other extras.
    public var isExtra: Bool

    public init(name: String, isNamed: Bool, isExtra: Bool) {
        self.name = name
        self.isNamed = isNamed
        self.isExtra = isExtra
    }
}

/// A state of the lexer's deterministic automaton over Unicode scalars.
public struct LexAutomatonState: Sendable, Equatable, Codable {
    /// The moves out of the state, sorted by scalar and disjoint.
    public var transitions: [LexTransition]
    /// The index of the token that the text read so far is, if the lexer stops here.
    public var accept: Int?

    public init(transitions: [LexTransition], accept: Int?) {
        self.transitions = transitions
        self.accept = accept
    }
}

/// A move of the lexer's automaton on one scalar of `lower ... upper`.
public struct LexTransition: Sendable, Equatable, Codable {
    public var lower: UInt32
    public var upper: UInt32
    public var target: Int
    /// Whether the scalar is a separator, such as whitespace, that comes before a token and is not part of it.
    public var skips: Bool

    public init(lower: UInt32, upper: UInt32, target: Int, skips: Bool) {
        self.lower = lower
        self.upper = upper
        self.target = target
        self.skips = skips
    }
}
