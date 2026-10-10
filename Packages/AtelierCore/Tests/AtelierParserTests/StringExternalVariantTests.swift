import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// A string external is valid wherever any of its token variants is. A string used in `token()` or `immediate_token()`
/// wrappers becomes several terminals, the bare `"}"` and numbered `"}"_N` variants, and Bash's `${A:-b}` closes on the
/// variant: the external's validity tested the bare terminal alone, so the scanner's concatenation branch emitted a
/// zero-width token at the brace and every such expansion parsed with an ERROR.
@Suite
struct StringExternalVariantTests {
    /// `block` closes with the bare `}`, which the string external names; `expansion` closes with the `"}"_N`
    /// variant that `immediate_token` gives the same text. The scanner reads a concatenation before that brace only
    /// when the external is not valid there.
    private static let grammar = GrammarDefinition(
        name: "string_external_variants",
        rules: [
            ("source", .choice([.symbol("block"), .symbol("expansion")])),
            ("block", .seq([.string("{"), .symbol("word"), .string("}")])),
            (
                "expansion",
                .seq([
                    .string("${"), .symbol("word"),
                    .choice([.seq([.symbol("CONCAT"), .symbol("word")]), .blank]),
                    .immediateToken(.string("}"))
                ])
            ),
            ("word", .pattern("[a-z]+"))
        ],
        extras: [.pattern(#"\s"#)],
        externals: [.symbol("CONCAT"), .string("}")])

    @Test
    func `a string external is valid where only a token variant of its text can follow`() throws {
        let table = try Self.compiled().parseTable

        #expect(table.terminals.contains("\"}\""))
        #expect(table.terminals.contains { $0.hasPrefix("\"}\"_") })

        // The state after `${ word`, the only one that shifts CONCAT.
        let concat = try #require(table.terminals.firstIndex(of: "CONCAT"))
        let state = try #require(
            (0 ..< table.stateCount)
                .first { state in
                    if case .shift = table.actions[state, concat] { return true }
                    return false
                })
        #expect(table.validExternals[state][1])
    }

    @Test
    func `an expansion closed by a variant brace parses without errors`() throws {
        let tree = try Self.parser().parse("${a}", externalScanner: ConcatenationScanner())

        #expect(tree.root.type == "source")
        #expect(tree.errorByteCount == 0)
    }

    @Test
    func `a block closed by the bare brace still parses`() throws {
        let tree = try Self.parser().parse("{a}", externalScanner: ConcatenationScanner())

        #expect(tree.root.type == "source")
        #expect(tree.errorByteCount == 0)
    }

    private static func compiled() throws -> ParseTableCompiler.CompilationResult {
        try ParseTableCompiler.compile(grammar)
    }

    private static func parser() throws -> GLRParser {
        let compiled = try compiled()
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }
}

/// Reads a zero-width `CONCAT` before a brace only when the brace is not valid, as the bash scanner's concatenation
/// branch does.
private struct ConcatenationScanner: GrammarExternalScanner {
    static let externalNames = ["CONCAT", "}"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols[0], !validSymbols[1], lexer.lookahead == UInt32(UInt8(ascii: "}")) else { return false }
        lexer.resultSymbol = 0
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}

    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}
