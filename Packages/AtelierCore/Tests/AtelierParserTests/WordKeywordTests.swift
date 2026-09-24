import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct WordKeywordTests {
    @Test
    func `a keyword spelling remains a word where the keyword is invalid`() throws {
        let grammar = GrammarDefinition(
            name: "contextual_word",
            rules: [
                ("source", .seq([.string("let"), .symbol("identifier")])),
                ("identifier", .pattern("[a-z]+"))
            ],
            word: "identifier")
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable,
            productions: compiled.productions)

        let tree = try parser.parse("let let")

        #expect(!tree.root.containsError)
        #expect(tree.root.children.map(\.type) == ["\"let\"", "identifier"])
    }
}
