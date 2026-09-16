import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct GrammarParserTests {
    @Test
    func `Grammar parser produces a tree`() throws {
        let json = """
            {
                "name": "inc_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"}
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = GrammarParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree1 = try parser.parse("x")
        let tree2 = try parser.parse("x")
        #expect(tree1.root.type != "")
        #expect(tree2.root.type != "")
    }
}
