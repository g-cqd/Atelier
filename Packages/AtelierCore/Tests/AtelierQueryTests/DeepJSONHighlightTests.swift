import Testing

@testable import AtelierParser
@testable import AtelierQuery

@Suite
struct DeepJSONHighlightTests {
    @Test
    func `JSON nested 5,000 arrays deep parses, queries and deallocates on a pool-sized stack`() async throws {
        let (parser, query) = try BundledJSONFixture.parserAndQuery()
        let source = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)

        let summary = await onThread { Self.highlight(source, parser: parser, query: query) }

        #expect(summary.rootType == "document")
        #expect(summary.depth > 10_000)
        #expect(summary.bracketCaptures == 10_000)
    }

    private struct Summary: Sendable {
        var rootType: String?
        var depth = 0
        var bracketCaptures = 0
    }

    /// Parses and queries `source` as KittyCode's file-open task does: the matches go before the tree, then the tree.
    private static func highlight(_ source: String, parser: GLRParser, query: Query) -> Summary {
        guard let tree = try? parser.parse(source) else { return Summary() }
        var summary = Summary(rootType: tree.root.type)
        tree.walk { _, depth in
            summary.depth = max(summary.depth, depth + 1)
            return true
        }
        summary.bracketCaptures = bracketCaptures(of: query, in: tree)
        return summary
    }

    private static func bracketCaptures(of query: Query, in tree: SyntaxTree) -> Int {
        QueryMatcher.execute(query: query, tree: tree)
            .reduce(0) { count, match in
                count + match.captures.count { $0.name == "punctuation.bracket" }
            }
    }
}
