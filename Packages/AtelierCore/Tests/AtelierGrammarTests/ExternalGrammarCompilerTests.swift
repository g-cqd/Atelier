import Testing

@testable import AtelierGrammar

@Suite
struct ExternalGrammarCompilerTests {
    @Test
    func `an inline rule contributes productions without a syntax node`() throws {
        let grammar = GrammarDefinition(
            name: "inline_rule",
            rules: [
                ("source", .seq([.symbol("_inline"), .string(";")])),
                ("_inline", .choice([.string("a"), .string("b")]))
            ],
            extras: [], inline: ["_inline"])

        let result = try ParseTableCompiler.compile(grammar)

        #expect(!result.parseTable.nonTerminals.contains("_inline"))
        #expect(result.productions.contains { $0.name == "source" && $0.symbols == ["\"a\"", "\";\""] })
        #expect(result.productions.contains { $0.name == "source" && $0.symbols == ["\"b\"", "\";\""] })
    }

    @Test
    func `Swift emoji properties compile as lexical patterns`() throws {
        let grammar = GrammarDefinition(
            name: "emoji_identifier",
            rules: [("source", .pattern(#"\p{Emoji}\p{EMod}?"#))], extras: [])

        let result = try ParseTableCompiler.compile(grammar)

        #expect(!result.lexTable.automaton.isEmpty)
    }
}
