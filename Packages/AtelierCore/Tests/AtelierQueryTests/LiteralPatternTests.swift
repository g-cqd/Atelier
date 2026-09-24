import Testing

@testable import AtelierParser
@testable import AtelierQuery

/// A quoted pattern, such as JSON's `":" @punctuation.delimiter`, names an anonymous node, as in tree-sitter.
@Suite
struct LiteralPatternTests {
    @Test
    func `A quoted pattern skips a named node with the same text`() throws {
        let (parser, _) = try BundledJSONFixture.parserAndQuery()
        let tree = try parser.parse(#"{"a": ":"}"#)

        let matches = QueryMatcher.execute(query: try QueryParser.parse(#"":" @delimiter"#), tree: tree)

        // The pair's colon, not the string content that reads ":".
        #expect(matches.flatMap(\.captures).map(\.node.byteRange) == [4 ..< 5])
    }

    @Test
    func `A quoted pattern matches an anonymous node by its bytes, a multi-byte one included`() throws {
        let arrow = SyntaxNode(type: "→", byteRange: 2 ..< 5, isNamed: false)
        let plus = SyntaxNode(type: "+", byteRange: 6 ..< 7, isNamed: false)
        let root = SyntaxNode(type: "expression", children: [arrow, plus], byteRange: 0 ..< 9)
        let tree = SyntaxTree(root: root, source: "a → + b")

        let query = try QueryParser.parse(#""→" @arrow "+" @plus "-" @minus "→→" @double"#)
        let captures = QueryMatcher.execute(query: query, tree: tree).flatMap(\.captures)

        #expect(captures.map(\.name) == ["arrow", "plus"])
        #expect(captures.map(\.node.byteRange) == [2 ..< 5, 6 ..< 7])
    }
}
