import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// An external token is offered to the scanner only where the parse can take it, as tree-sitter offers it: tree-sitter
/// never merges two states when that would make an external token valid in one of them. Swift's corpus case
/// `@Test⏎class Empty { }` failed because the state after `Test` shared the lookaheads of every other place an
/// identifier ends, `_implicit_semi` among them, so the scanner ended the attribute with a semicolon.
@Suite
struct ContextualExternalValidityTests {
    /// `a x⏎` ends with a scanner semicolon; in `(x⏎)` the same `x` is followed by `)`, where no semicolon is valid.
    private static let grammar = GrammarDefinition(
        name: "contextual_semicolons",
        rules: [
            (
                "source",
                .choice([
                    .seq([.string("a"), .symbol("value"), .symbol("SEMI")]),
                    .seq([.string("("), .symbol("value"), .string(")")])
                ])
            ),
            ("value", .choice([.string("x"), .string("z")]))
        ],
        extras: [.pattern(#"\s"#)],
        externals: [.symbol("SEMI")])

    @Test
    func `a newline ends the value with a scanner semicolon where one is valid`() throws {
        let tree = try Self.parser().parse("ax\n", externalScanner: NewlineSemicolonScanner())

        #expect(tree.errorByteCount == 0)
        #expect(tree.root.children.map(\.type) == ["\"a\"", "value", "SEMI"])
    }

    @Test
    func `the scanner is not offered a semicolon where the same value is followed by a parenthesis`() throws {
        let tree = try Self.parser().parse("(x\n)", externalScanner: NewlineSemicolonScanner())

        #expect(tree.errorByteCount == 0)
        #expect(tree.root.children.map(\.type) == ["\"(\"", "value", "\")\""])
    }

    private static func parser() throws -> GLRParser {
        let compiled = try ParseTableCompiler.compile(grammar)
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }
}

/// Reads a newline as `SEMI` wherever the parser offers `SEMI`, as Swift's and JavaScript's scanners end statements.
private struct NewlineSemicolonScanner: GrammarExternalScanner {
    static let externalNames = ["SEMI"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "\n")) else { return false }
        lexer.advance(skip: false)
        lexer.resultSymbol = 0
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}

    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}
