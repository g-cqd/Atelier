/// Optimizes keyword matching using the grammar's `word` token.
///
/// When a grammar defines a `word` token (e.g., identifier pattern `[a-zA-Z_]\w*`),
/// keywords that match the word pattern can be recognized by first matching the word
/// pattern and then checking a keyword table, avoiding backtracking in the lexer.
public enum KeywordExtractor: Sendable {

    /// Extracts keywords from the grammar that match the word pattern.
    public static func extract(from grammar: GrammarDefinition) -> [String: String] {
        guard grammar.word != nil else { return [:] }

        // Find all string literals used in the grammar
        var keywords: [String: String] = [:] // keyword string → rule name that uses it

        for (name, rule) in grammar.rules {
            extractKeywords(from: rule, ruleName: name, into: &keywords)
        }

        // Filter to only those that look like identifiers (matching the word pattern)
        // Since we don't have the actual word regex, we use a simple heuristic:
        // keywords are alphabetic-only or alphanumeric starting with a letter
        return keywords.filter { key, _ in
            isWordLike(key)
        }
    }

    private static func extractKeywords(from rule: Rule, ruleName: String, into keywords: inout [String: String]) {
        switch rule {
        case .string(let value):
            keywords[value] = ruleName
        case .seq(let members):
            for m in members { extractKeywords(from: m, ruleName: ruleName, into: &keywords) }
        case .choice(let members):
            for m in members { extractKeywords(from: m, ruleName: ruleName, into: &keywords) }
        case .repeat(let content), .repeat1(let content), .optional(let content):
            extractKeywords(from: content, ruleName: ruleName, into: &keywords)
        case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content),
             .precDynamic(_, let content):
            extractKeywords(from: content, ruleName: ruleName, into: &keywords)
        case .token(let content), .immediateToken(let content):
            extractKeywords(from: content, ruleName: ruleName, into: &keywords)
        case .field(_, let content):
            extractKeywords(from: content, ruleName: ruleName, into: &keywords)
        case .alias(let content, _, _):
            extractKeywords(from: content, ruleName: ruleName, into: &keywords)
        case .symbol, .pattern, .blank:
            break
        }
    }

    private static func isWordLike(_ str: String) -> Bool {
        guard let first = str.first else { return false }
        guard first.isLetter || first == "_" else { return false }
        return str.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
