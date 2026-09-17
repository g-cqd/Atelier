public import AtelierSyntaxModel

/// The grammar tier behind the shared engine interface: tree-sitter grammars parsed by the GLR parser, queried for
/// captures, and emitted as structural tokens. A language is supported once its artifacts are loaded
/// (`LanguageHighlighter.ensureArtifacts(for:)`) and its grammar needs no external scanner.
public struct GrammarHighlightEngine: HighlightEngine {
    public init() {}

    public var layer: HighlightLayer { .structural }

    public func supports(_ language: Language) -> Bool {
        guard let name = Self.grammarName(of: language) else { return false }
        return LanguageHighlighter.makeSession(language: name, preferGrammar: true).isGrammarBacked
    }

    public func highlight(utf8 source: [UInt8], language: Language) -> [HighlightToken] {
        guard let name = Self.grammarName(of: language) else { return [] }
        let session = LanguageHighlighter.makeSession(language: name, preferGrammar: true)
        guard session.isGrammarBacked else { return [] }
        return session.highlightDocumentTokens(source: String(decoding: source, as: UTF8.self))
    }

    /// The bundled grammar manifest's name for a language; nil for the languages no grammar ships for.
    static func grammarName(of language: Language) -> String? {
        switch language {
            case .shell: "bash"
            case .plain, .objectiveC, .fish: nil
            default: language.name
        }
    }
}
