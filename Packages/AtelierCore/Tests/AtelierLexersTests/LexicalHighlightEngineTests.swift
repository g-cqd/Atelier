import AtelierSyntaxModel
import Testing

@testable import AtelierLexers

/// The scanners behind the shared engine interface.
struct LexicalHighlightEngineTests {
    @Test
    func `tokens carry the lexical layer and the role of their kind`() {
        let engine = LexicalHighlightEngine()
        let source = Array("let n = 1 // c".utf8)
        let tokens = engine.highlight(utf8: source, language: .swift)
        #expect(tokens.map(\.role) == [.keyword, .number, .comment])
        #expect(tokens.allSatisfy { $0.layer == .lexical && $0.modifiers.isEmpty })
        #expect(tokens.map(\.byteRange) == SyntaxHighlighter.tokens(utf8: source, language: .swift).map(\.range))
    }

    @Test(arguments: [
        (TokenKind.keyword, HighlightRole.keyword), (.string, .string), (.comment, .comment), (.number, .number),
        (.type, .type), (.attribute, .attribute), (.tag, .tag), (.attributeName, .property), (.entity, .escape)
    ])
    func `every token kind maps to one role`(kind: TokenKind, role: HighlightRole) {
        #expect(kind.role == role)
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
