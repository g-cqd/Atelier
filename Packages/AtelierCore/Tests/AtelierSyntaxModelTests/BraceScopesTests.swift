import Testing

@testable import AtelierSyntaxModel

/// The scopes of a text without a parse (DIFF-03): its braces matched in order, those in strings and comments left out.
struct BraceScopesTests {
    @Test
    func `braces are matched in order, outer scope first`() {
        let text = "a { b { c } d { e } }"

        let bytes = Array(text.utf8)

        let scopes = SyntaxScope.braces(in: bytes.span, skipping: [])

        #expect(scopes.map(\.range) == [2 ..< 21, 6 ..< 11, 14 ..< 19])
        #expect(scopes.allSatisfy { $0.kind == .block })
    }

    @Test
    func `braces in strings and comments count for nothing, and unmatched ones open no scope`() {
        let text = #"} f { s = "{"; // }"# + "\n}\n{"
        let string = HighlightToken(byteRange: 10 ..< 13, role: .string, layer: .lexical)
        let comment = HighlightToken(byteRange: 15 ..< 19, role: .comment, layer: .lexical)
        let bytes = Array(text.utf8)

        let scopes = SyntaxScope.braces(in: bytes.span, skipping: [string, comment])

        #expect(scopes.map(\.range) == [4 ..< 21])
    }
}
