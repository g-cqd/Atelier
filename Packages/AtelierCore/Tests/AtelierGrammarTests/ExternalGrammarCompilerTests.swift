import Testing

@testable import AtelierGrammar

@Suite
struct ExternalGrammarCompilerTests {
    @Test
    func `a nullable lexical pattern compiles without making its rule optional`() throws {
        let grammar = GrammarDefinition(
            name: "nullable_token",
            rules: [("source", .seq([.string("#!"), .pattern("[^\\r\\n]*")]))],
            extras: [])

        let result = try ParseTableCompiler.compile(grammar)

        #expect(result.lexTable.tokens.contains { $0.name == "source_token1" })
        #expect(result.productions.contains { $0.symbols == ["\"#!\"", "source_token1"] })
    }

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
    func `word extracts literal keywords for contextual classification`() throws {
        let grammar = GrammarDefinition(
            name: "word",
            rules: [
                ("source", .seq([.string("let"), .symbol("identifier")])),
                ("identifier", .pattern("[a-z]+"))
            ],
            extras: [], word: "identifier")

        let result = try ParseTableCompiler.compile(grammar)

        #expect(result.lexTable.wordToken != nil)
        #expect(result.lexTable.keywordTokens["let"] != nil)
        #expect(result.lexTable.modeValidTokens.count == result.lexTable.modeStarts.count)
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
