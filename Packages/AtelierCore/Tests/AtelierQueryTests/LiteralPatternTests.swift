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
}
