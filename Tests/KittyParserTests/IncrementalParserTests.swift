import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct IncrementalParserTests {
    @Test
    func `Incremental parse produces tree`() throws {
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

        let parser = IncrementalParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree1 = try parser.parse("x")
        let tree2 = try parser.parse("x", oldTree: tree1)
        #expect(tree2.root.type != "")
    }
}
