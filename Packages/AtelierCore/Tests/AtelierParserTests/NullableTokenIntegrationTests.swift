import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct NullableTokenIntegrationTests {
    @Test
    func `a nullable word leaves literals and whitespace available`() throws {
        let grammar = GrammarDefinition(
            name: "nullable_word",
            rules: [
                ("source", .seq([.string("a"), .symbol("word")])),
                ("word", .pattern("[a-z]*"))
            ],
            extras: [.pattern(#"\s"#)])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("a foo")

        #expect(!tree.root.containsError)
        #expect(tree.root.byteRange == 0 ..< 5)
    }

    @Test
    func `an optional literal beats a nullable word in the same mode`() throws {
        let grammar = GrammarDefinition(
            name: "optional_literal",
            rules: [
                ("source", .seq([.optional(.string("a")), .symbol("word")])),
                ("word", .pattern("[a-z]*"))
            ],
            extras: [])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("a")

        #expect(!tree.root.containsError)
        var tokenTypes: [String] = []
        tree.walk { node, _ in
            if node.children.isEmpty { tokenTypes.append(node.type) }
            return true
        }
        #expect(tokenTypes.contains("\"a\""))
    }

    @Test
    func `a repeated nullable token does not loop at one position`() throws {
        let grammar = GrammarDefinition(
            name: "nullable_repeat", rules: [("source", .repeat(.pattern("x*")))], extras: [])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("y")

        #expect(tree.root.containsError)
        #expect(tree.root.byteRange == 0 ..< 1)
    }
}
