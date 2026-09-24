import Foundation

// MARK: - Grammar Definition (tree-sitter grammar.json format)

public struct GrammarDefinition: Sendable, Equatable {
    /// The extras of a grammar that names none: whitespace, as tree-sitter's grammar DSL gives such a grammar.
    public static let defaultExtras: [Rule] = [.pattern(#"\s"#)]

    public var name: String
    public var rules: [(name: String, rule: Rule)]
    /// What may appear between any two tokens: separators such as whitespace, which the lexer skips, and tokens such
    /// as comments, which the parser sets aside. Empty, nothing may.
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
        extras: [Rule] = defaultExtras,
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

// MARK: - Precedence

/// A rule's precedence: a number, or a name the grammar's `precedences` lists order against other names and symbols.
public enum Precedence: Sendable, Hashable, ExpressibleByIntegerLiteral {
    case integer(Int)
    case name(String)

    public init(integerLiteral value: Int) {
        self = .integer(value)
    }

    /// The number a lexical rule completes with: a named precedence orders syntactic rules only, and counts as 0.
    var lexicalValue: Int {
        if case .integer(let value) = self { return value }
        return 0
    }
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
    case prec(Precedence, Rule)
    case precLeft(Precedence, Rule)
    case precRight(Precedence, Rule)
    case precDynamic(Int, Rule)
    case token(Rule)
    case immediateToken(Rule)
    case field(String, Rule)
    case alias(Rule, String, Bool)  // rule, name, isNamed
    case blank
}

// MARK: - Grammar Error

public enum GrammarError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case invalidJSON(String)
    case missingField(String)
    case invalidRuleType(String)
    case resourceLimitExceeded(String)
    case unsupportedVersion(Int)
}
