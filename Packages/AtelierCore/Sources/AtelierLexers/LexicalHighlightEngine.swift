public import AtelierSyntaxModel

/// The scanners as the lexical tier: every language they know gets keyword, string, comment, number, type,
/// attribute, tag and entity tokens at ``HighlightLayer/lexical``.
public struct LexicalHighlightEngine: HighlightEngine {
    public init() {}

    public var layer: HighlightLayer { .lexical }

    public func supports(_ language: Language) -> Bool {
        language != .plain
    }

    public func highlight(utf8 source: [UInt8], language: Language) -> [HighlightToken] {
        highlight(utf8: source.span, language: language)
    }

    /// Lexical tokens over borrowed UTF-8 bytes, with byte offsets. The scan's `Token`s are mapped to
    /// ``HighlightToken``s, one more array a scan: AemiLexers builds only its own token type (aemi ADR 0022).
    /// - Complexity: O(bytes + tokens)
    public func highlight(utf8 source: Span<UInt8>, language: Language) -> [HighlightToken] {
        SyntaxHighlighter.tokens(utf8: source, language: language).map(Self.highlightToken)
    }

    /// Tokens over UTF-16 units with UTF-16 offsets in `byteRange`, for a store that indexes by UTF-16 unit.
    public func highlight(utf16 source: [UInt16], language: Language) -> [HighlightToken] {
        SyntaxHighlighter.tokens(utf16: source, language: language).map(Self.highlightToken)
    }

    static func highlightToken(_ token: Token) -> HighlightToken {
        HighlightToken(byteRange: token.range, role: token.kind.role, layer: .lexical)
    }
}
