/// A grammar split, as tree-sitter prepares one, into the tokens the lexer reads and the syntactic rules over them.
///
/// Every string, pattern and `token(…)` in a rule becomes a token, identical ones shared, and the rule refers to it by
/// name: a string by its text in quotes, anything else as `<rule>_token<n>`. A rule other than the first whose whole
/// body is a token used nowhere else becomes that token, named after the rule, as JSON's `number`, `true` and
/// `string_content` do; the parse tree then has one leaf for it instead of a node over one leaf per character.
struct LexicalGrammar: Sendable {
    private(set) var tokens: [LexicalToken] = []
    /// The extras that are no token: what the lexer skips before a token, whitespace when a grammar names no extras.
    private(set) var separators: [Rule] = []
    /// The grammar's rules, the first rule first, with each lexical part replaced by the symbol of its token and the
    /// rules that became tokens left out.
    private(set) var syntacticRules: [(name: String, rule: Rule)] = []

    private var usageCounts: [Int] = []
    private var tokenIndices: [String: Int] = [:]
    private var tokensPerRule: [String: Int] = [:]

    init(_ grammar: GrammarDefinition) {
        var rules: [(name: String, rule: Rule)] = []
        for (name, rule) in grammar.rules {
            rules.append((name, extractingTokens(from: rule, in: name)))
        }

        let ruleNames = Set(grammar.rules.map(\.name))
        for (offset, rule) in rules.enumerated() {
            if offset > 0, case .symbol(let symbol) = rule.rule, !ruleNames.contains(symbol),
                let token = tokenIndices[symbol], usageCounts[token] == 1
            {
                tokens[token].name = rule.name
                tokens[token].isNamed = !rule.name.hasPrefix("_")
                continue
            }
            syntacticRules.append(rule)
        }

        for extra in grammar.extras {
            markExtra(extra)
        }
        if grammar.extras.isEmpty {
            separators = [.pattern(#"\s"#)]
        }
    }

    /// `rule` with each of its lexical parts replaced by the symbol of a token.
    private mutating func extractingTokens(from rule: Rule, in ruleName: String) -> Rule {
        switch rule {
            case .string(let value):
                return .symbol(token(for: rule, isImmediate: false, text: value, in: ruleName))
            case .pattern:
                return .symbol(token(for: rule, isImmediate: false, text: nil, in: ruleName))
            case .token(let content):
                return .symbol(token(for: content, isImmediate: false, text: Self.text(of: content), in: ruleName))
            case .immediateToken(let content):
                return .symbol(token(for: content, isImmediate: true, text: Self.text(of: content), in: ruleName))
            case .seq(let members):
                return .seq(extractingTokens(from: members, in: ruleName))
            case .choice(let members):
                return .choice(extractingTokens(from: members, in: ruleName))
            case .repeat(let content):
                return .repeat(extractingTokens(from: content, in: ruleName))
            case .repeat1(let content):
                return .repeat1(extractingTokens(from: content, in: ruleName))
            case .optional(let content):
                return .optional(extractingTokens(from: content, in: ruleName))
            case .prec(let value, let content):
                return .prec(value, extractingTokens(from: content, in: ruleName))
            case .precLeft(let value, let content):
                return .precLeft(value, extractingTokens(from: content, in: ruleName))
            case .precRight(let value, let content):
                return .precRight(value, extractingTokens(from: content, in: ruleName))
            case .precDynamic(let value, let content):
                return .precDynamic(value, extractingTokens(from: content, in: ruleName))
            case .field(let name, let content):
                return .field(name, extractingTokens(from: content, in: ruleName))
            case .alias(let content, let value, let isNamed):
                return .alias(extractingTokens(from: content, in: ruleName), value, isNamed)
            case .symbol, .blank:
                return rule
        }
    }

    private mutating func extractingTokens(from members: [Rule], in ruleName: String) -> [Rule] {
        var extracted: [Rule] = []
        extracted.reserveCapacity(members.count)
        for member in members {
            extracted.append(extractingTokens(from: member, in: ruleName))
        }
        return extracted
    }

    /// The name of the token for `rule`, one already made for the same rule if there is one.
    private mutating func token(for rule: Rule, isImmediate: Bool, text: String?, in ruleName: String) -> String {
        if let existing = tokens.indices.first(where: {
            tokens[$0].rule == rule && tokens[$0].isImmediate == isImmediate
        }) {
            usageCounts[existing] += 1
            return tokens[existing].name
        }
        var name: String
        if let text {
            name = "\"" + text + "\""
        } else {
            tokensPerRule[ruleName, default: 0] += 1
            name = "\(ruleName)_token\(tokensPerRule[ruleName, default: 0])"
        }
        // Two tokens of one text differ in immediacy or precedence; the parse table needs two names for them.
        if tokenIndices[name] != nil {
            name += "_\(tokens.count)"
        }
        tokenIndices[name] = tokens.count
        usageCounts.append(1)
        tokens.append(
            LexicalToken(
                name: name,
                rule: rule,
                isImmediate: isImmediate,
                completionPrecedence: Self.completionPrecedence(of: rule),
                implicitPrecedence: (text == nil ? 0 : 2) + (isImmediate ? 1 : 0)
            ))
        return name
    }

    /// Marks the token `extra` names or is as an extra; an extra that is no token is a separator. An extra naming a
    /// rule that did not become a token is left out: the parser has no way to skip a node it must build.
    private mutating func markExtra(_ extra: Rule) {
        if case .symbol(let name) = extra {
            if let index = tokens.firstIndex(where: { $0.name == name }) {
                tokens[index].isExtra = true
            }
            return
        }
        let (rule, isImmediate): (Rule, Bool) =
            switch extra {
                case .token(let content): (content, false)
                case .immediateToken(let content): (content, true)
                default: (extra, false)
            }
        if let index = tokens.firstIndex(where: { $0.rule == rule && $0.isImmediate == isImmediate }) {
            tokens[index].isExtra = true
        } else {
            separators.append(extra)
        }
    }

    /// The text of a token that is one string, under any precedence: tree-sitter names such a token by its text.
    private static func text(of rule: Rule) -> String? {
        switch rule {
            case .string(let value): value
            case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content): text(of: content)
            default: nil
        }
    }

    /// The precedence a token completes with: that of a `prec` around its whole text.
    private static func completionPrecedence(of rule: Rule) -> Int {
        switch rule {
            case .prec(let value, _), .precLeft(let value, _), .precRight(let value, _): value
            default: 0
        }
    }
}
