import Foundation

// MARK: - Grammar Definition (tree-sitter grammar.json format)

public struct GrammarDefinition: Sendable, Equatable {
    public var name: String
    public var rules: [(name: String, rule: Rule)]
    public var extras: [Rule]
    public var conflicts: [[String]]
    public var externals: [Rule]
    public var inline: [String]
    public var word: String?
    public var supertypes: [String]
    public var precedences: [[PrecedenceEntry]]

    public init(
        name: String,
        rules: [(name: String, rule: Rule)],
        extras: [Rule] = [],
        conflicts: [[String]] = [],
        externals: [Rule] = [],
        inline: [String] = [],
        word: String? = nil,
        supertypes: [String] = [],
        precedences: [[PrecedenceEntry]] = []
    ) {
        self.name = name
        self.rules = rules
        self.extras = extras
        self.conflicts = conflicts
        self.externals = externals
        self.inline = inline
        self.word = word
        self.supertypes = supertypes
        self.precedences = precedences
    }

    public static func == (lhs: GrammarDefinition, rhs: GrammarDefinition) -> Bool {
        guard lhs.name == rhs.name else { return false }
        guard lhs.rules.count == rhs.rules.count else { return false }
        for (l, r) in zip(lhs.rules, rhs.rules) {
            guard l.name == r.name && l.rule == r.rule else { return false }
        }
        return lhs.extras == rhs.extras
            && lhs.conflicts == rhs.conflicts
            && lhs.externals == rhs.externals
            && lhs.inline == rhs.inline
            && lhs.word == rhs.word
            && lhs.supertypes == rhs.supertypes
            && lhs.precedences == rhs.precedences
    }
}

// MARK: - Precedence Entry

public enum PrecedenceEntry: Sendable, Equatable {
    case symbol(String)
    case literal(String)
}

// MARK: - Rule

public indirect enum Rule: Sendable, Equatable {
    case symbol(String)
    case string(String)
    case pattern(String)
    case seq([Rule])
    case choice([Rule])
    case `repeat`(Rule)
    case repeat1(Rule)
    case optional(Rule)
    case prec(Int, Rule)
    case precLeft(Int, Rule)
    case precRight(Int, Rule)
    case precDynamic(Int, Rule)
    case token(Rule)
    case immediateToken(Rule)
    case field(String, Rule)
    case alias(Rule, String, Bool) // rule, name, isNamed
    case blank
}

// MARK: - Grammar Error

public enum GrammarError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case invalidJSON(String)
    case missingField(String)
    case invalidRuleType(String)
    case unsupportedVersion(Int)
}
