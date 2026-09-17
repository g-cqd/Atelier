import AtelierLexers
import AtelierSyntaxModel
import Testing

@testable import KittySyntax

/// The grammar tier as a `HighlightEngine`, next to the lexical one.
struct GrammarHighlightEngineTests {
    @Test
    func `the engine is the structural tier and declines what has no grammar`() {
        let engine = GrammarHighlightEngine()
        #expect(engine.layer == .structural)
        #expect(LexicalHighlightEngine().layer == .lexical)
        #expect(!engine.supports(.plain))
        #expect(!engine.supports(.objectiveC))
        #expect(GrammarHighlightEngine.grammarName(of: .shell) == "bash")
        #expect(GrammarHighlightEngine.grammarName(of: .cpp) == "cpp")
    }

    @Test
    func `a loaded grammar is supported and its tokens are the session's structural tokens`() async {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let engine = GrammarHighlightEngine()
        let source = Array("{\"a\": 1}".utf8)
        #expect(available)
        #expect(engine.supports(.json))
        let session = LanguageHighlighter.makeSession(language: "json", preferGrammar: true)
        #expect(
            engine.highlight(utf8: source, language: .json) == session.highlightDocumentTokens(source: "{\"a\": 1}"))
        // g-cqd/Atelier#2: the bundled JSON grammar yields no tree today, so both are empty until it is fixed.
        #expect(engine.highlight(utf8: source, language: .json).isEmpty)
    }
}
