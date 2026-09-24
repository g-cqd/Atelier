import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct ExternalScannerErrorCleanupTests {
    @Test(.timeLimit(.minutes(1)))
    func `invalid scanner tokens release a deep tree on a small stack`() async throws {
        let grammar = GrammarDefinition(
            name: "nested_external_error",
            rules: [
                ("source", .symbol("nested")),
                (
                    "nested",
                    .choice([
                        .seq([.string("["), .symbol("nested"), .string("]")]),
                        .string("x")
                    ])
                )
            ],
            extras: [.symbol("SENTINEL")], externals: [.symbol("SENTINEL")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable,
            productions: compiled.productions)
        let depth = 2_300
        let source = String(repeating: "[", count: depth) + "x" + String(repeating: "]", count: depth)

        let failure: ParseError? = await onThread { () -> ParseError? in
            do {
                _ = try parser.parse(source, externalScanner: InvalidEOFScanner())
                return nil
            } catch {
                return error as? ParseError
            }
        }

        #expect(failure == .parsingFailed("External scanner returned an invalid token"))
    }
}

private struct InvalidEOFScanner: GrammarExternalScanner {
    static let externalNames = ["SENTINEL"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard lexer.isAtEnd else { return false }
        lexer.resultSymbol = 1
        return true
    }

    func serialize(into buffer: inout [UInt8]) {}
    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}
