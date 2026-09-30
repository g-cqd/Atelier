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
    func `a literal external shares the internal token terminal`() throws {
        let grammar = GrammarDefinition(
            name: "shared_external",
            rules: [("source", .string("x"))], extras: [], externals: [.string("x")])

        let result = try ParseTableCompiler.compile(grammar)

        #expect(result.parseTable.externalNames == ["x"])
        #expect(result.parseTable.externalSymbols == ["\"x\""])
        #expect(result.parseTable.validExternals[0] == [true])
        #expect(result.lexTable.tokens.contains { $0.name == "\"x\"" })
    }

    @Test
    func `a pattern external shares its lexical token terminal`() throws {
        let grammar = GrammarDefinition(
            name: "pattern_external",
            rules: [("source", .pattern("x+"))], extras: [], externals: [.pattern("x+")])

        let compiled = try ParseTableCompiler.compile(grammar)
        let token = try #require(compiled.lexTable.tokens.first?.name)

        #expect(compiled.parseTable.externalNames == ["x+"])
        #expect(compiled.parseTable.externalSymbols == [token])
        #expect(compiled.parseTable.validExternals[0] == [true])
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

    /// Tree-sitter resolves precedence first and consults `conflicts` only for the actions precedence leaves, so a
    /// declaration, whichever rules it names, keeps no reduction precedence rules out.
    @Test(arguments: [[["A", "B"]], [["A"]], []])
    func `precedence resolves competing reductions whatever conflicts the grammar declares`(conflicts: [[String]])
        throws
    {
        let grammar = GrammarDefinition(
            name: "declared_conflict",
            rules: [
                ("source", .choice([.symbol("A"), .symbol("B")])),
                ("A", .prec(1, .seq([.string("x")]))),
                ("B", .prec(2, .seq([.string("x")])))
            ],
            extras: [], conflicts: conflicts)

        let compiled = try ParseTableCompiler.compile(grammar)
        let reductions = compiled.parseTable.actions.rows.flatMap { $0 }
            .compactMap { action -> String? in
                if case .reduce(_, _, let nonTerminal) = action { return nonTerminal }
                return nil
            }

        #expect(
            !compiled.parseTable.actions.rows.flatMap { $0 }.contains { if case .conflict = $0 { true } else { false } }
        )
        #expect(reductions.contains("B"))
        #expect(!reductions.contains("A"))
    }

    @Test
    func `precedence resolves a shift against a reduction before a declared conflict`() throws {
        let grammar = GrammarDefinition(
            name: "shift_reduce_conflict",
            rules: [
                ("source", .seq([.choice([.symbol("A"), .symbol("B")]), .string("y")])),
                ("A", .prec(2, .seq([.string("x"), .string("y")]))),
                ("B", .prec(1, .seq([.string("x")])))
            ],
            extras: [], conflicts: [["A", "B"]])

        let compiled = try ParseTableCompiler.compile(grammar)
        let hasConflict = compiled.parseTable.actions.rows.flatMap { $0 }
            .contains { if case .conflict = $0 { true } else { false } }

        #expect(!hasConflict)
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
