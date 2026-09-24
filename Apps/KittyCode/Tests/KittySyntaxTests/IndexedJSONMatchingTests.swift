import AtelierGrammar
import AtelierParser
import Foundation
import Testing

@testable import AtelierQuery
@testable import KittySyntax

/// The bundled JSON query over a parse of the bundled JSON grammar finds the same matches whether the matcher tries
/// every pattern at every node or only those its index gives for the node's type.
struct IndexedJSONMatchingTests {
    @Test
    func `indexed matching gives identical matches over a json document`() throws {
        let resources = try #require(KittySyntaxResources.bundle.resourcePath)
        let grammar = try GrammarLoader.load(from: "\(resources)/Grammars/json/grammar.json")
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let query = try QueryParser.parse(
            String(contentsOfFile: "\(resources)/Grammars/json/highlights.scm", encoding: .utf8))
        let source = #"""
            {"name": "a \"quoted\" value\n", "count": -1.5e3, "ok": true, "none": null,
             "items": [1, "two", [false, {"deep": ["é"]}]], "empty": {}, "list": []}
            """#
        let tree = try parser.parse(source)

        let indexed = QueryMatcher.execute(query: query, tree: tree)
        #expect(indexed == QueryMatcher.executeTryingEveryPattern(query: query, tree: tree))
        #expect(indexed.count > 40)
    }
}
