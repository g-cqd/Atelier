import Testing

@testable import AtelierParser
@testable import AtelierQuery

/// A query numbers its captures once, so a highlighter resolves each capture name once per query and reads it by
/// index.
struct CaptureNumberingTests {
    @Test
    func `a query lists each capture name once, in the order its text first names it`() throws {
        let query = try QueryParser.parse(
            """
            (pair key: (string) @property) @pair
            (string) @string
            ["null" "true"] @constant
            (comment) @comment @spell
            (string) @property
            """)
        #expect(query.captureNames == ["property", "pair", "string", "constant", "comment", "spell"])
    }

    @Test
    func `every capture of a pattern and of a match carries its name's index`() throws {
        let key = SyntaxNode(type: "string", byteRange: 0 ..< 1)
        let colon = SyntaxNode(type: ":", byteRange: 1 ..< 2, isNamed: false)
        let value = SyntaxNode(type: "string", byteRange: 2 ..< 3)
        let pair = SyntaxNode(
            type: "pair", children: [key, colon, value], byteRange: 0 ..< 3, fields: ["key": [key]])
        let tree = SyntaxTree(root: SyntaxNode(type: "document", children: [pair], byteRange: 0 ..< 3), source: "k:v")
        let query = try QueryParser.parse(
            """
            (pair key: (string) @property) @pair
            (string) @string
            ":" @delimiter
            (string) @property
            """)

        var patternCaptures: [QueryPattern.Capture] = []
        for pattern in query.patterns { Self.collectCaptures(pattern, into: &patternCaptures) }
        #expect(patternCaptures.map(\.index) == [0, 1, 2, 3, 0])
        #expect(patternCaptures.allSatisfy { query.captureNames[$0.index] == $0.name })

        let captures = QueryMatcher.execute(query: query, tree: tree).flatMap(\.captures)
        #expect(captures.count == 7)  // the pair 2, each string 2, the colon 1
        #expect(captures.allSatisfy { query.captureNames[$0.index] == $0.name })
    }

    @Test
    func `a query built from patterns numbers their captures as a parsed one does`() throws {
        let query = Query(patterns: [
            .nodeMatch(type: "a", children: [], capture: "x"), .wildcard(capture: "y"), .literal("z", capture: "x")
        ])
        #expect(query.captureNames == ["x", "y"])
        guard case .literal(_, let capture) = query.patterns[2] else {
            Issue.record("expected a literal")
            return
        }
        #expect(capture?.index == 0)
        #expect(query == (try QueryParser.parse(#"(a) @x _ @y "z" @x"#)))
    }

    private static func collectCaptures(_ pattern: QueryPattern, into captures: inout [QueryPattern.Capture]) {
        switch pattern {
            case .nodeMatch(_, let children, let capture):
                for child in children { collectCaptures(child, into: &captures) }
                if let capture { captures.append(capture) }
            case .literal(_, let capture), .wildcard(let capture):
                if let capture { captures.append(capture) }
            case .fieldMatch(_, let inner), .quantified(let inner, _):
                collectCaptures(inner, into: &captures)
            case .alternation(let patterns), .sequence(let patterns):
                for inner in patterns { collectCaptures(inner, into: &captures) }
            case .negatedField, .predicate, .anchor:
                break
        }
    }
}
