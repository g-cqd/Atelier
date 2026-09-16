public import AtelierSyntaxModel

/// Token boundaries per line for the syntax tier of the intraline diff, so the diff does not decide which parser a
/// language gets: the app injects a swift-syntax backed provider for Swift, the default is a code-aware lexer.
public protocol SyntaxTokenRanging: Sendable {
    /// - Parameters:
    ///   - text: The whole side, lines separated by `\n`.
    ///   - language: The language the text is written in.
    /// - Returns: One array per line of `text`, of UTF-16 ranges relative to the line, ascending and disjoint.
    func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]]
}

/// The lexer-based provider: words, string literals kept whole, and `@`/`#` directives glued to their name.
public struct CodeTokenRanges: SyntaxTokenRanging {
    public init() {}

    /// - Complexity: O(text)
    public func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]] {
        DiffModel.lines(of: text).map { IntralineTokenizer.codeTokens(Array($0.utf16)) }
    }
}
