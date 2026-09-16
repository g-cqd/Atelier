import Testing

@testable import KittyParser
@testable import KittyQuery

@Suite
struct QueryCursorTests {
    @Test
    func `Iterate matches`() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")
        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])

        var cursor = QueryCursor(query: query, tree: tree)
        let match = cursor.next()
        _ = try #require(match)
        #expect(cursor.next() == nil)
    }
}
