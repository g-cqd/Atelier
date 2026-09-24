import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Where a state's lex mode reads nothing, tree-sitter lexes in the error state's mode, calling the scanner again with
/// every external valid, and the parse goes on with the token if the state takes it. Swift's scanner reads `#if` only
/// where a raw string may start; its corpus case “#if directive inside class body” reads the directive that way.
@Suite
struct ExternalErrorModeTests {
    @Test
    func `a token only the scanner's error mode reads is taken where the state expects it`() throws {
        let grammar = GrammarDefinition(
            name: "directive_after_member",
            rules: [
                (
                    "source",
                    .choice([
                        .seq([.string("a"), .string(";"), .symbol("DIRECTIVE")]), .seq([.string("x"), .symbol("RAW")])
                    ])
                )
            ],
            extras: [.pattern(#"\s"#)],
            externals: [.symbol("RAW"), .symbol("DIRECTIVE")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("a; #if", externalScanner: HashDirectiveScanner())

        #expect(tree.errorByteCount == 0)
        #expect(tree.root.children.map(\.type) == ["\"a\"", "\";\"", "DIRECTIVE"])
    }
}

/// Reads `#if` as `DIRECTIVE`, but only when `RAW` is valid too, as Swift's scanner reads its directives.
private struct HashDirectiveScanner: GrammarExternalScanner {
    static let externalNames = ["RAW", "DIRECTIVE"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        while lexer.lookahead == UInt32(UInt8(ascii: " ")) { lexer.advance(skip: true) }
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "#")) else { return false }
        for byte in "#if".utf8 {
            guard lexer.lookahead == UInt32(byte) else { return false }
            lexer.advance(skip: false)
        }
        lexer.resultSymbol = 1
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}

    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}
