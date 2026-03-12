import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct GLRParserTests {
    @Test
    func `Parse produces syntax tree`() throws {
        // Build a minimal grammar and parse table
        let json = """
            {
                "name": "minimal",
                "rules": {
                    "source": {"type": "STRING", "value": "hello"}
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let parser = GLRParser(
            parseTable: result.parseTable,
            lexTable: result.lexTable,
            productions: result.productions
        )

        let tree = try parser.parse("hello")
        #expect(tree.root.type != "")
    }

    @Test
    func `Parse continues reducing later stacks after an earlier conflict`() throws {
        let parser = GLRParser(
            parseTable: makeConflictParseTable(),
            lexTable: LexTable(),
            productions: [
                ProductionRule(name: "_start", symbolCount: 1, symbols: ["Good"]),
                ProductionRule(name: "Bad", symbolCount: 2, symbols: ["a", "ERROR"]),
                ProductionRule(name: "BadSingle", symbolCount: 1, symbols: ["ERROR"]),
                ProductionRule(
                    name: "Good", symbolCount: 2, symbols: ["a", "b"], fields: [1: "rhs"]),
            ]
        )

        let tree = try parser.parse("ab")

        #expect(tree.root.type == "Good")
        #expect(tree.root.children.map(\.type) == ["a", "b"])
        #expect(tree.root.child(forField: "rhs")?.type == "b")
    }
}
