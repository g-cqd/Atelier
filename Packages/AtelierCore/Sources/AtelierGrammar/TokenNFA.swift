/// A token of a grammar, as the lexer's automaton is built from it.
struct LexicalToken: Sendable, Equatable {
    /// The terminal's name in the parse table, and the type of the token's leaf nodes.
    var name: String
    /// Its text: strings, patterns and their combinations, with lexical precedences.
    var rule: Rule
    /// Whether it must start where the previous token ended, with no separator before it.
    var isImmediate = false
    var isNamed = false
    /// Whether the parser skips it rather than shifting it, as it does the grammar's comments.
    var isExtra = false
    /// The precedence it completes with, which beats a longer match of a token of lower precedence.
    var completionPrecedence = 0
    /// Breaks ties between tokens of equal precedence: a string beats a pattern, an immediate token a plain one.
    var implicitPrecedence = 0

    /// What choosing between this token and another reads of it.
    var priority: LexTokenPriority {
        LexTokenPriority(
            completionPrecedence: completionPrecedence, implicitPrecedence: implicitPrecedence, isImmediate: isImmediate
        )
    }
}

/// How a token ranks when several could end at one place, and whether it may follow a separator: all the lexer's
/// automaton needs of a token besides its path through the ``TokenNFA``.
struct LexTokenPriority: Sendable, Equatable, Codable {
    var completionPrecedence: Int
    var implicitPrecedence: Int
    var isImmediate: Bool
}

/// A nondeterministic automaton over Unicode scalars for a grammar's tokens, built as tree-sitter builds its lexical
/// one: each token has its own path from its own start state, and a token that may follow a separator starts with a
/// loop over the separators, whose moves are marked so the lexer can leave them out of the token.
struct TokenNFA: Sendable, Equatable, Codable {
    enum State: Sendable, Equatable, Codable {
        /// Reads one scalar of `characters` and moves to `next`, inside a `prec` of `precedence`.
        case advance(ScalarRanges, next: Int, precedence: Int, isSeparator: Bool)
        /// Moves, reading nothing, to each of the states.
        case split([Int])
        /// Ends `token`, which completes with `precedence`.
        case accept(token: Int, precedence: Int)
    }

    /// The most states an automaton may have: a count in a pattern copies its operand, so a few patterns could
    /// otherwise make millions.
    static let maxStates = 200_000

    private(set) var states: [State] = []
    /// The token each state belongs to.
    private(set) var owners: [Int] = []
    /// Each token's start state, by token index.
    private(set) var starts: [Int] = []
    /// Tokens whose rule reaches its accept state without reading a scalar.
    private(set) var nullableTokens: Set<Int> = []

    /// The patterns parsed so far, by source; only building the automaton reads them.
    private var patterns: [String: PatternNode] = [:]

    private enum CodingKeys: String, CodingKey {
        case states, owners, starts, nullableTokens
    }

    /// The automaton made of its parts, as a table file's reader read them.
    init(states: [State], owners: [Int], starts: [Int], nullableTokens: Set<Int>) {
        self.states = states
        self.owners = owners
        self.starts = starts
        self.nullableTokens = nullableTokens
    }

    static func == (lhs: TokenNFA, rhs: TokenNFA) -> Bool {
        lhs.states == rhs.states && lhs.owners == rhs.owners && lhs.starts == rhs.starts
            && lhs.nullableTokens == rhs.nullableTokens
    }

    /// - Throws: `GrammarError.invalidRuleType` for a token that names a rule or has a pattern it can't parse;
    ///   `.resourceLimitExceeded` past
    ///   ``maxStates``.
    init(tokens: [LexicalToken], separators: [Rule]) throws(GrammarError) {
        let separatorLoop: Rule? = separators.isEmpty ? nil : .repeat(.choice(separators))
        for (index, token) in tokens.enumerated() {
            let accept = add(.accept(token: index, precedence: token.completionPrecedence), owner: index)
            var start = try expand(token.rule, next: accept, in: Context(owner: index))
            if closure(of: [start]).contains(accept) { nullableTokens.insert(index) }
            if !token.isImmediate, let separatorLoop {
                start = try expand(separatorLoop, next: start, in: Context(owner: index, isSeparator: true))
            }
            starts.append(start)
        }
    }

    /// What a state being built belongs to.
    private struct Context {
        var owner: Int
        var precedence = 0
        var isSeparator = false
    }

    private mutating func add(_ state: State, owner: Int) -> Int {
        states.append(state)
        owners.append(owner)
        return states.count - 1
    }

    /// The start of a path that reads `rule` and then goes on to `next`.
    private mutating func expand(_ rule: Rule, next: Int, in context: Context) throws(GrammarError) -> Int {
        guard states.count < Self.maxStates else {
            throw .resourceLimitExceeded("Token automaton exceeded limit (\(Self.maxStates) states)")
        }
        switch rule {
            case .string(let value):
                var start = next
                for scalar in value.unicodeScalars.reversed() {
                    start = add(
                        .advance(
                            ScalarRanges(scalar: scalar.value), next: start, precedence: context.precedence,
                            isSeparator: context.isSeparator),
                        owner: context.owner)
                }
                return start
            case .pattern(let pattern):
                return try expand(try parsedPattern(pattern), next: next, in: context)
            case .seq(let members):
                var start = next
                for member in members.reversed() {
                    start = try expand(member, next: start, in: context)
                }
                return start
            case .choice(let members):
                var starts: [Int] = []
                for member in members {
                    starts.append(try expand(member, next: next, in: context))
                }
                return add(.split(starts), owner: context.owner)
            case .repeat(let content), .repeat1(let content):
                let entries = try loop(next: next, in: context) { builder, loop throws(GrammarError) in
                    try builder.expand(content, next: loop, in: context)
                }
                return if case .repeat = rule { entries.loop } else { entries.body }
            case .optional(let content):
                let body = try expand(content, next: next, in: context)
                return add(.split([body, next]), owner: context.owner)
            case .blank:
                return next
            case .prec(let value, let content), .precLeft(let value, let content), .precRight(let value, let content):
                var inner = context
                inner.precedence = value.lexicalValue
                return try expand(content, next: next, in: inner)
            case .precDynamic(_, let content), .token(let content), .immediateToken(let content),
                .field(_, let content), .alias(let content, _, _):
                return try expand(content, next: next, in: context)
            case .symbol(let name):
                throw .invalidRuleType("Rule `\(name)` is used inside a token")
        }
    }

    private mutating func expand(_ node: PatternNode, next: Int, in context: Context) throws(GrammarError) -> Int {
        guard states.count < Self.maxStates else {
            throw .resourceLimitExceeded("Token automaton exceeded limit (\(Self.maxStates) states)")
        }
        switch node {
            case .characters(let characters):
                return add(
                    .advance(characters, next: next, precedence: context.precedence, isSeparator: context.isSeparator),
                    owner: context.owner)
            case .sequence(let items):
                var start = next
                for item in items.reversed() {
                    start = try expand(item, next: start, in: context)
                }
                return start
            case .alternation(let branches):
                var starts: [Int] = []
                for branch in branches {
                    starts.append(try expand(branch, next: next, in: context))
                }
                return add(.split(starts), owner: context.owner)
            case .repetition(let operand, let minimum, let maximum):
                var start: Int
                if let maximum {
                    // Each optional copy may end the repetition: `a{0,2}` is `(a(a)?)?`.
                    start = next
                    for _ in minimum ..< maximum {
                        let body = try expand(operand, next: start, in: context)
                        start = add(.split([body, next]), owner: context.owner)
                    }
                } else {
                    let entries = try loop(next: next, in: context) { builder, loop throws(GrammarError) in
                        try builder.expand(operand, next: loop, in: context)
                    }
                    start = entries.loop
                }
                for _ in 0 ..< minimum {
                    start = try expand(operand, next: start, in: context)
                }
                return start
        }
    }

    /// The tokens whose first scalar may also be the first scalar of a separator, such as the text of a string, which
    /// may start with a space: in a mode that holds them, such a token reads the separator before another token as its
    /// own text, and so outruns that token.
    /// - Complexity: O(n) in the automaton's states, per token.
    func tokensStartingLikeSeparators() -> Set<Int> {
        var separatorFirst = ScalarRanges.empty
        var tokenFirst = [ScalarRanges](repeating: .empty, count: starts.count)
        for (token, start) in starts.enumerated() {
            for state in closure(of: [start]) {
                guard case .advance(let characters, _, _, let isSeparator) = states[state] else { continue }
                if isSeparator {
                    separatorFirst = separatorFirst.union(characters)
                } else {
                    tokenFirst[token] = tokenFirst[token].union(characters)
                }
            }
        }
        return Set(tokenFirst.indices.filter { !tokenFirst[$0].intersection(separatorFirst).isEmpty })
    }

    /// A loop that reads what `body` builds any number of times, then goes on to `next`: `loop` enters it and may
    /// leave at once, `body` enters it through one pass of the body.
    private mutating func loop(
        next: Int,
        in context: Context,
        body build: (inout TokenNFA, Int) throws(GrammarError) -> Int
    ) throws(GrammarError) -> (loop: Int, body: Int) {
        let loop = add(.split([]), owner: context.owner)
        let body = try build(&self, loop)
        states[loop] = .split([body, next])
        return (loop, body)
    }

    private mutating func parsedPattern(_ pattern: String) throws(GrammarError) -> PatternNode {
        if let parsed = patterns[pattern] {
            return parsed
        }
        let parsed = try PatternParser.parse(pattern)
        patterns[pattern] = parsed
        return parsed
    }

    /// The states `starts` reach without reading a scalar, splits left out: sorted, the key of a lexer state.
    func closure(of starts: [Int]) -> [Int] {
        var seen = Set<Int>()
        var pending = starts
        var reached: [Int] = []
        while let state = pending.popLast() {
            guard seen.insert(state).inserted else { continue }
            if case .split(let targets) = states[state] {
                pending.append(contentsOf: targets)
            } else {
                reached.append(state)
            }
        }
        return reached.sorted()
    }
}
