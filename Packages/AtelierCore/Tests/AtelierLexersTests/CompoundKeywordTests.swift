import AtelierSyntaxModel
import Testing

@testable import AtelierLexers

/// Keywords the word scan cannot see on its own: ones holding a byte that ends a word, and a block comment that starts
/// with the line comment's marker.
struct CompoundKeywordTests {
    private func tokens(_ text: String, _ language: Language) -> [Token] {
        SyntaxHighlighter.tokens(utf8: Array(text.utf8), language: language)
    }

    @Test
    func `ruby's defined? is one keyword`() {
        #expect(tokens("x = defined?(y)", .ruby).contains(Token(kind: .keyword, range: 4 ..< 12)))
    }

    @Test
    func `java's non-sealed is one keyword`() {
        #expect(tokens("non-sealed class A {}", .java).first == Token(kind: .keyword, range: 0 ..< 10))
    }

    @Test
    func `a word running on past a compound keyword is not one`() {
        #expect(!tokens("defined?x", .ruby).contains { $0.kind == .keyword })
        #expect(!tokens("non-sealedness", .java).contains { $0.kind == .keyword })
    }

    @Test
    func `a compound keyword at the end of the text is still one`() {
        #expect(tokens("defined?", .ruby) == [Token(kind: .keyword, range: 0 ..< 8)])
    }

    @Test
    func `lua's block comment spans its lines`() {
        #expect(tokens("--[[ one\ntwo ]] x = 1", .lua).first == Token(kind: .comment, range: 0 ..< 15))
    }

    @Test
    func `lua's line comment still ends its line`() {
        #expect(tokens("-- one\nx = 1", .lua).first == Token(kind: .comment, range: 0 ..< 6))
    }
}
