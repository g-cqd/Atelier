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

extension TokenKind {
    /// The role a scanner token carries into the shared model.
    public var role: HighlightRole {
        switch self {
            case .keyword: .keyword
            case .string: .string
            case .comment: .comment
            case .number: .number
            case .type: .type
            case .attribute: .attribute
            case .tag: .tag
            case .attributeName: .property
            case .entity: .escape
        }
    }
}
