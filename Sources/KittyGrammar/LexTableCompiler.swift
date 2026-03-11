/// Compiles terminal tokens from a grammar into a lexer DFA (LexTable).
public enum LexTableCompiler: Sendable {

    /// Extract string/pattern tokens and compile into a LexTable.
    public static func compile(_ grammar: GrammarDefinition) -> LexTable {
        var keywords: [String: Int] = [:]
        var tokenID = 0

        // Extract all string literals as keywords
        for (_, rule) in grammar.rules {
            extractTokens(from: rule, keywords: &keywords, tokenID: &tokenID)
        }
        for rule in grammar.extras {
            extractTokens(from: rule, keywords: &keywords, tokenID: &tokenID)
        }

        // Build a simple trie-based DFA for keywords
        let states = buildTrieDFA(keywords: keywords)

        // Extract comment patterns from extras
        let commentPatterns = extractCommentPatterns(from: grammar)

        return LexTable(states: states, keywords: keywords, commentPatterns: commentPatterns)
    }

    // MARK: - Private

    private static func extractTokens(from rule: Rule, keywords: inout [String: Int], tokenID: inout Int) {
        switch rule {
        case .string(let value):
            if keywords[value] == nil {
                keywords[value] = tokenID
                tokenID += 1
            }
        case .seq(let members):
            for m in members { extractTokens(from: m, keywords: &keywords, tokenID: &tokenID) }
        case .choice(let members):
            for m in members { extractTokens(from: m, keywords: &keywords, tokenID: &tokenID) }
        case .repeat(let content), .repeat1(let content), .optional(let content):
            extractTokens(from: content, keywords: &keywords, tokenID: &tokenID)
        case .prec(_, let content), .precLeft(_, let content), .precRight(_, let content),
             .precDynamic(_, let content):
            extractTokens(from: content, keywords: &keywords, tokenID: &tokenID)
        case .token(let content), .immediateToken(let content):
            extractTokens(from: content, keywords: &keywords, tokenID: &tokenID)
        case .field(_, let content):
            extractTokens(from: content, keywords: &keywords, tokenID: &tokenID)
        case .alias(let content, _, _):
            extractTokens(from: content, keywords: &keywords, tokenID: &tokenID)
        case .symbol, .pattern, .blank:
            break
        }
    }

    // MARK: - Comment Pattern Extraction

    private static func extractCommentPatterns(from grammar: GrammarDefinition) -> [CommentPattern] {
        var patterns: [CommentPattern] = []
        let ruleMap = Dictionary(grammar.rules.map { ($0.name, $0.rule) }, uniquingKeysWith: { first, _ in first })

        for extra in grammar.extras {
            if case .symbol(let name) = extra, let rule = ruleMap[name] {
                extractCommentPatternsFromRule(rule, into: &patterns)
            }
        }
        return patterns
    }

    private static func extractCommentPatternsFromRule(_ rule: Rule, into patterns: inout [CommentPattern]) {
        switch rule {
        case .token(let content), .immediateToken(let content):
            extractCommentPatternsFromRule(content, into: &patterns)
        case .choice(let members):
            for m in members { extractCommentPatternsFromRule(m, into: &patterns) }
        case .seq(let members):
            if let first = members.first {
                extractCommentPatternsFromRule(first, into: &patterns)
            }
        case .pattern(let regex):
            if let cp = classifyCommentRegex(regex) {
                patterns.append(cp)
            }
        case .prec(_, let c), .precLeft(_, let c), .precRight(_, let c), .precDynamic(_, let c):
            extractCommentPatternsFromRule(c, into: &patterns)
        default:
            break
        }
    }

    private static func classifyCommentRegex(_ regex: String) -> CommentPattern? {
        let prefix = extractLiteralPrefix(from: regex)
        guard prefix.count >= 1 else { return nil }

        // Block comment: starts with /* and regex contains closing */
        if prefix.hasPrefix("/*") {
            return .block(open: "/*", close: "*/")
        }
        // Line comment: starts with //, #, --, or ;;
        if prefix.hasPrefix("//") || prefix.hasPrefix("#") || prefix.hasPrefix("--") || prefix.hasPrefix(";;") {
            return .line(prefix: prefix)
        }
        return nil
    }

    /// Extracts the leading literal characters from a tree-sitter regex pattern.
    private static func extractLiteralPrefix(from regex: String) -> String {
        var result = ""
        let chars = Array(regex.unicodeScalars)
        var i = 0

        while i < chars.count && result.count < 4 {
            let ch = chars[i]
            if ch == "\\" && i + 1 < chars.count {
                let escaped = chars[i + 1]
                // Common regex escapes for literal characters
                if "/.*+?[](){}|^$\\".unicodeScalars.contains(escaped) {
                    result.append(Character(escaped))
                    i += 2
                    // Handle quantifier like {2,3} — repeat the char to its minimum
                    if i < chars.count && chars[i] == "{" {
                        let qStart = i + 1
                        var qEnd = qStart
                        while qEnd < chars.count && chars[qEnd] != "," && chars[qEnd] != "}" { qEnd += 1 }
                        if let minCount = Int(String(chars[qStart..<qEnd].map { Character($0) })), minCount > 1 {
                            result.append(contentsOf: repeatElement(Character(escaped), count: minCount - 1))
                        }
                        while i < chars.count && chars[i] != "}" { i += 1 }
                        if i < chars.count { i += 1 }
                    }
                } else {
                    break
                }
            } else if ch.properties.isAlphabetic || ch.properties.isASCIIHexDigit || ch == "_" || ch == "-" || ch == " " || ch == "#" || ch == ";" {
                result.append(Character(ch))
                i += 1
            } else {
                break
            }
        }

        return result
    }

    // MARK: - Trie DFA

    private static func buildTrieDFA(keywords: [String: Int]) -> [LexState] {
        guard !keywords.isEmpty else { return [LexState()] }

        // Build a trie
        struct TrieNode {
            var children: [UInt32: Int] = [:] // char → node index
            var accepting: Int? = nil
        }

        var nodes = [TrieNode()]  // root = 0

        for (keyword, id) in keywords {
            var current = 0
            for scalar in keyword.unicodeScalars {
                let charVal = scalar.value
                if let next = nodes[current].children[charVal] {
                    current = next
                } else {
                    let newIdx = nodes.count
                    nodes.append(TrieNode())
                    nodes[current].children[charVal] = newIdx
                    current = newIdx
                }
            }
            nodes[current].accepting = id
        }

        // Convert trie to LexState array
        return nodes.map { node in
            let transitions = node.children.sorted(by: { $0.key < $1.key }).map { (charVal, nextIdx) in
                (charVal...charVal, nextIdx)
            }
            return LexState(transitions: transitions, accepting: node.accepting)
        }
    }
}
