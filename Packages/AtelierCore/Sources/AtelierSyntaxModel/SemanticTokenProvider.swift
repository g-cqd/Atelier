/// Protocol for providing semantic tokens for a document.
/// Implementors (e.g. an LSP client) return `HighlightToken`s at the `.semantic` layer.
public protocol SemanticTokenProvider: Sendable {
    /// Return semantic tokens for the given document URI.
    func semanticTokens(for documentURI: String) async throws -> [HighlightToken]
}
