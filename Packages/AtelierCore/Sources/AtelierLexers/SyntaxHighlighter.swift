public import AtelierSyntaxModel

public enum TokenKind: Sendable {
    case keyword
    case string
    case comment
    case number
    case type
    case attribute
    case tag
    case attributeName
    case entity
}

/// A syntax token with a range in UTF-16 offsets.
public struct Token: Sendable, Equatable {
    public let kind: TokenKind
    public let range: Range<Int>

    public init(kind: TokenKind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// Hand-rolled scanners over UTF-16 units, so token offsets map directly onto NSRange without conversion.
public enum SyntaxHighlighter {
    public static func tokens(in text: String, language: Language) -> [Token] {
        let units = Array(text.utf16)
        switch language {
            case .swift, .objectiveC, .kotlin, .java, .javascript, .typescript, .c, .cpp, .python, .shell, .fish:
                var scanner = CodeScanner(units: units, syntax: LanguageSyntax.syntax(for: language))
                return scanner.scan()
            case .html:
                var scanner = HTMLScanner(units: units)
                return scanner.scan()
            case .css:
                var scanner = CSSScanner(units: units)
                return scanner.scan()
            case .json, .yaml, .toml:
                var scanner = DataScanner(units: units, format: language)
                return scanner.scan()
            case .plain:
                return []
        }
    }

    /// Splits tokens at line boundaries and rebases them on their line.
    /// - Parameters:
    ///   - tokens: Tokens over the whole text, ascending and disjoint.
    ///   - lineStarts: UTF-16 offset of each line's first unit, ascending.
    ///   - textLength: UTF-16 length of the whole text, which ends the last line.
    /// - Returns: One token array per line, with ranges relative to the line start.
    /// - Complexity: O(tokens + lines)
    public static func tokensByLine(_ tokens: [Token], lineStarts: [Int], textLength: Int) -> [[Token]] {
        var result = [[Token]](repeating: [], count: lineStarts.count)
        var line = 0
        for token in tokens {
            while line + 1 < lineStarts.count, lineStarts[line + 1] <= token.range.lowerBound {
                line += 1
            }
            var current = line
            while current < lineStarts.count, lineStarts[current] < token.range.upperBound {
                let base = lineStarts[current]
                let lineEnd = current + 1 < lineStarts.count ? lineStarts[current + 1] - 1 : textLength
                let start = max(token.range.lowerBound, base)
                let end = min(token.range.upperBound, lineEnd)
                if end > start {
                    result[current].append(Token(kind: token.kind, range: (start - base) ..< (end - base)))
                }
                current += 1
            }
        }
        return result
    }
}
