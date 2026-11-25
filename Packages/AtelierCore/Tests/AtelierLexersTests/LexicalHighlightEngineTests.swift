import AtelierLexers
import AtelierSyntaxModel
import Testing

/// The scanners behind the shared engine interface.
struct LexicalHighlightEngineTests {
    @Test
    func `tokens carry the lexical layer and the role of their kind`() {
        let engine = LexicalHighlightEngine()
        let source = Array("let n = 1 // c".utf8)
        let tokens = engine.highlight(utf8: source, language: .swift)
        #expect(tokens.map(\.role) == [.keyword, .number, .comment])
        #expect(tokens.allSatisfy { $0.layer == .lexical && $0.modifiers.isEmpty })
        #expect(tokens.map(\.byteRange) == SyntaxHighlighter.tokens(utf8: source, language: .swift).map(\.byteRange))
    }

    @Test(arguments: Language.allCases)
    func `the engine keeps the scanners' tokens as they come`(language: Language) {
        let source = Array(LexerCorpus.text(language, fragments: 50, seed: 1).utf8)
        let tokens = LexicalHighlightEngine().highlight(utf8: source, language: language)

        #expect(tokens == SyntaxHighlighter.tokens(utf8: source, language: language))
        #expect(tokens.allSatisfy { $0.layer == .lexical && $0.modifiers.isEmpty })
    }

    @Test
    func `plain text is the one language the engine declines`() {
        let engine = LexicalHighlightEngine()
        #expect(!engine.supports(.plain))
        #expect(Language.allCases.filter { $0 != .plain }.allSatisfy(engine.supports))
        #expect(engine.highlight(utf8: Array("x".utf8), language: .plain).isEmpty)
    }

    @Test
    func `utf16 highlighting reports utf16 offsets`() {
        let text = "é = \"x\""
        let tokens = LexicalHighlightEngine().highlight(utf16: Array(text.utf16), language: .swift)
        #expect(tokens.map(\.byteRange) == [4 ..< 7])
    }
}
