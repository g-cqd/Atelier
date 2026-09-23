import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import AtelierQuery

/// A node a grammar renames with `alias` answers to the new name in queries, as tree-sitter's highlight queries expect.
@Suite
struct AliasedNodeQueryTests {
    @Test
    func `An aliased node type matches its query`() throws {
        let tree = try Self.parse("hello ;")

        let matches = QueryMatcher.execute(query: try QueryParser.parse("(greeting) @greeting"), tree: tree)

        #expect(matches.flatMap(\.captures).map { $0.node.text(from: tree.source) } == ["hello"])
    }

    @Test
    func `An aliased node no longer answers to its rule's name`() throws {
        let tree = try Self.parse("hello ;")

        let matches = QueryMatcher.execute(query: try QueryParser.parse("(word) @word"), tree: tree)

        #expect(matches.isEmpty)
    }

    /// `source: seq(alias($.word, $.greeting), ";")` with `word: "hello"`.
    private static func parse(_ source: String) throws -> SyntaxTree {
        let json = """
            {
                "name": "aliased",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [
                            {
                                "type": "ALIAS",
                                "content": {"type": "SYMBOL", "name": "word"},
                                "value": "greeting",
                                "named": true
                            },
                            {"type": "STRING", "value": ";"}
                        ]
                    },
                    "word": {"type": "STRING", "value": "hello"}
                }
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        return try parser.parse(source)
    }
}
