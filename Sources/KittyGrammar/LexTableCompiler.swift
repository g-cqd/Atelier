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

        return LexTable(states: states, keywords: keywords)
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
