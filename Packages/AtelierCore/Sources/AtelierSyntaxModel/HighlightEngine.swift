/// One tier of highlighting, from the lexical scanners to a grammar parser to a language server: each yields
/// role-carrying tokens over bytes, and the merger stacks the tiers by layer.
public protocol HighlightEngine: Sendable {
    /// The layer the engine's tokens carry, which decides precedence when tiers overlap.
    var layer: HighlightLayer { get }

    /// Whether the engine has anything to say about `language`.
    func supports(_ language: Language) -> Bool

    /// Tokens over the UTF-8 bytes of a source, ascending and disjoint, with byte ranges.
    func highlight(utf8 source: [UInt8], language: Language) -> [HighlightToken]
}
