import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// A shift that precedence resolved against a reduction the merged lookaheads of another context made is taken where
/// that reduction leads nowhere: tree-sitter's state holds one context and has no conflict to resolve. Swift's
/// `statements` is `prec.left`, so after a statement's semicolon a merged lookahead `weak` ended the statements
/// instead of starting `weak var x = y`, and the corpus case “Contextual keywords are usable as identifiers” failed.
@Suite
struct LostShiftTests {
    /// In braces the statements are followed by `}`; in parentheses by `w`, which may also start a statement.
    private static let grammar = GrammarDefinition(
        name: "merged_statements",
        rules: [
            (
                "source",
                .choice([
                    .seq([.string("{"), .symbol("statements"), .string("}")]),
                    .seq([.string("("), .symbol("statements"), .string("w")])
                ])
            ),
            (
                "statements",
                .precLeft(
                    0,
                    .seq([
                        .symbol("statement"), .repeat(.seq([.string(";"), .symbol("statement")])),
                        .optional(.string(";"))
                    ]))
            ),
            ("statement", .choice([.string("x"), .seq([.string("w"), .string("x")])]))
        ],
        extras: [.pattern(#"\s"#)])

    @Test
    func `a statement after a semicolon is shifted where the merged reduction leads nowhere`() throws {
        let compiled = try ParseTableCompiler.compile(Self.grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("{ x ; w x }")

        #expect(tree.errorByteCount == 0)
        #expect(tree.root.type == "source")
    }
}
