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
    func `declared conflicts preserve competing reductions across precedence`() throws {
        let grammar = GrammarDefinition(
            name: "declared_conflict",
            rules: [
                ("source", .choice([.symbol("A"), .symbol("B")])),
                ("A", .prec(1, .seq([.string("x")]))),
                ("B", .prec(2, .seq([.string("x")])))
            ],
            extras: [], conflicts: [["A", "B"]])

        let compiled = try ParseTableCompiler.compile(grammar)
        let preservesBoth = compiled.parseTable.actions.flatMap { $0 }
            .contains { action in
                guard case .conflict(let actions) = action else { return false }
                return actions.filter { if case .reduce = $0 { true } else { false } }.count == 2
            }

        #expect(preservesBoth)
    }

    @Test(arguments: [["A"], []])
    func `a declared conflict names every competing rule`(declaration: [String]) throws {
        let grammar = GrammarDefinition(
            name: "partial_conflict",
            rules: [
                ("source", .choice([.symbol("A"), .symbol("B")])),
                ("A", .prec(1, .seq([.string("x")]))),
                ("B", .prec(2, .seq([.string("x")])))
            ],
            extras: [], conflicts: [declaration])

        let compiled = try ParseTableCompiler.compile(grammar)
        let hasConflict = compiled.parseTable.actions.flatMap { $0 }
            .contains { action in
                if case .conflict = action { return true }
                return false
            }

        #expect(!hasConflict)
    }

    @Test
    func `declared conflicts preserve a shift and a reduction`() throws {
        let grammar = GrammarDefinition(
            name: "shift_reduce_conflict",
            rules: [
                ("source", .seq([.choice([.symbol("A"), .symbol("B")]), .string("y")])),
                ("A", .prec(2, .seq([.string("x"), .string("y")]))),
                ("B", .prec(1, .seq([.string("x")])))
            ],
            extras: [], conflicts: [["A", "B"]])

        let compiled = try ParseTableCompiler.compile(grammar)
        let preservesBoth = compiled.parseTable.actions.flatMap { $0 }
            .contains { action in
                guard case .conflict(let actions) = action else { return false }
                return actions.contains { if case .reduce = $0 { true } else { false } }
                    && actions.contains { if case .shift = $0 { true } else { false } }
            }

        #expect(preservesBoth)
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
