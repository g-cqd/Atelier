/// Protocol for lexical-layer highlighting (Tier 1: keywords, strings, comments).
public protocol LexicalHighlightProvider: Sendable {
    func highlight(source: String, language: String?) -> [HighlightToken]
}

/// Protocol for structural-layer highlighting (Tier 2: tree-sitter grammar-backed).
public protocol StructuralHighlightProvider: Sendable {
    func highlight(source: String) -> [HighlightToken]
}
