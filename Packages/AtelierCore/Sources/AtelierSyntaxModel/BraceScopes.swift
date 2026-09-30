extension SyntaxScope {
    /// The scopes of a text no parse knows (DIFF-03): its curly braces matched in order, those inside a string or a
    /// comment token of `tokens` left out, so a brace written in a literal never opens or closes one. A closing brace
    /// with nothing open is skipped, and a brace left open at the end opens no scope. Each scope is a ``Kind/block``.
    /// - Parameters:
    ///   - utf8: The text's bytes.
    ///   - tokens: The lexer's tokens over the whole text, in UTF-8 offsets, ascending by start.
    /// - Returns: The scopes by their opening brace, an enclosing scope before those it holds.
    /// - Complexity: O(bytes + tokens)
    public static func braces(in utf8: Span<UInt8>, skipping tokens: [HighlightToken]) -> [SyntaxScope] {
        var opens: [Int] = []
        var closes: [Int] = []
        var open: [Int] = []
        var token = 0
        var index = 0
        let count = utf8.count
        while index < count {
            while token < tokens.count, tokens[token].byteRange.upperBound <= index { token += 1 }
            var skip = token
            while skip < tokens.count, tokens[skip].byteRange.lowerBound <= index {
                if tokens[skip].byteRange.contains(index), hidesBraces(tokens[skip].role) { break }
                skip += 1
            }
            if skip < tokens.count, tokens[skip].byteRange.lowerBound <= index {
                index = tokens[skip].byteRange.upperBound
                continue
            }
            switch utf8[index] {
                case UInt8(ascii: "{"):
                    open.append(opens.count)
                    opens.append(index)
                    closes.append(-1)
                case UInt8(ascii: "}"):
                    if let scope = open.popLast() { closes[scope] = index + 1 }
                default:
                    break
            }
            index += 1
        }
        var scopes: [SyntaxScope] = []
        scopes.reserveCapacity(opens.count - open.count)
        for (start, end) in zip(opens, closes) where end > start {
            scopes.append(SyntaxScope(range: start ..< end, kind: .block))
        }
        return scopes
    }

    /// Whether a token of `role` is a string or a comment, whose braces are text.
    private static func hidesBraces(_ role: HighlightRole) -> Bool {
        switch SymbolKinds.kind(of: role) {
            case .literal, .comment: true
            default: false
        }
    }
}
