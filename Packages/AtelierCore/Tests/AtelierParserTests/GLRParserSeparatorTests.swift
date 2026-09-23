import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// What the lexer skips between tokens: the grammar's extras that are no token, whitespace when it names none.
@Suite
struct GLRParserSeparatorTests {
    @Test
    func `A grammar that names no extras skips whitespace between tokens`() throws {
        let tree = try Self.parse("a b", extras: nil)

        #expect(tree.root.type == "source")
        #expect(!tree.root.containsError)
    }

    @Test
    func `A grammar whose extras are empty skips nothing`() throws {
        let tree = try Self.parse("a b", extras: "[]")

        #expect(tree.root.containsError)
    }

    /// `source: seq("a", "b")`, with `extras` as its extras member, or without one.
    private static func parse(_ source: String, extras: String?) throws -> SyntaxTree {
        let extrasMember = extras.map { #", "extras": \#($0)"# } ?? ""
        let json = """
            {
                "name": "pair",
                "rules": {
                    "source": {"type": "SEQ", "members": [{"type": "STRING", "value": "a"}, {"type": "STRING", "value": "b"}]}
                }\(extrasMember)
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        return try parser.parse(source)
    }
}
