import Testing

@testable import AtelierParser
@testable import AtelierQuery

@Suite
struct QueryMatcherTests {
    @Test
    func `Match node by type`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test
    func `Wildcard matches any node`() {
        let node = SyntaxNode(type: "anything", byteRange: 0 ..< 3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.wildcard(capture: "any")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count >= 1)
    }

    @Test
    func `Match within byte range`() {
        let node1 = SyntaxNode(type: "identifier", byteRange: 0 ..< 3)
        let node2 = SyntaxNode(type: "identifier", byteRange: 10 ..< 13)
        let root = SyntaxNode(type: "source", children: [node1, node2], byteRange: 0 ..< 13)
        let tree = SyntaxTree(root: root, source: "abc       def")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree, byteRange: 0 ..< 5)
        #expect(matches.count == 1)
    }

    @Test
    func `Parenthesized predicate filters a captured node match`() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 4)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 4)
        let tree = SyntaxTree(root: root, source: "self")

        let query = try QueryParser.parse("(identifier) @var (#eq? @var \"self\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test
    func `Wildcard predicate filters wildcard matches`() throws {
        let comment = SyntaxNode(type: "comment", byteRange: 0 ..< 4)
        let root = SyntaxNode(type: "source", children: [comment], byteRange: 0 ..< 7)
        let tree = SyntaxTree(root: root, source: "NOTE();")

        let query = try QueryParser.parse("(_) @comment (#match? @comment \"^NOTE$\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.node == comment)
        #expect(matches[0].captures.first?.name == "comment")
    }

    @Test
    func `Positional child matching respects order`() {
        let identifier = SyntaxNode(type: "identifier", byteRange: 0 ..< 1)
        let number = SyntaxNode(type: "number", byteRange: 1 ..< 2)
        let matchingCall = SyntaxNode(
            type: "call", children: [identifier, number], byteRange: 0 ..< 2)
        let reversedCall = SyntaxNode(
            type: "call", children: [number, identifier], byteRange: 0 ..< 2)

        let query = Query(patterns: [
            .nodeMatch(
                type: "call",
                children: [
                    .nodeMatch(type: "identifier", children: [], capture: "first"),
                    .nodeMatch(type: "number", children: [], capture: "second")
                ],
                capture: nil
            )
        ])

        let matchingTree = SyntaxTree(root: matchingCall, source: "ab")
        let reversedTree = SyntaxTree(root: reversedCall, source: "ab")

        let matchingResults = QueryMatcher.execute(query: query, tree: matchingTree)
        let reversedResults = QueryMatcher.execute(query: query, tree: reversedTree)

        #expect(matchingResults.count == 1)
        #expect(matchingResults[0].captures.map(\.name) == ["first", "second"])
        #expect(reversedResults.isEmpty)
    }

    @Test
    func `Positional child matching does not reuse the same child`() {
        let identifier = SyntaxNode(type: "identifier", byteRange: 0 ..< 1)
        let call = SyntaxNode(type: "call", children: [identifier], byteRange: 0 ..< 1)
        let tree = SyntaxTree(root: call, source: "a")

        let query = Query(patterns: [
            .nodeMatch(
                type: "call",
                children: [
                    .nodeMatch(type: "identifier", children: [], capture: "first"),
                    .nodeMatch(type: "identifier", children: [], capture: "second")
                ],
                capture: nil
            )
        ])

        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.isEmpty)
    }

    @Test
    func `Quantified oneOrMore matches multiple children`() {
        let a = SyntaxNode(type: "identifier", byteRange: 0 ..< 1)
        let b = SyntaxNode(type: "identifier", byteRange: 1 ..< 2)
        let parent = SyntaxNode(type: "list", children: [a, b], byteRange: 0 ..< 2)
        let tree = SyntaxTree(root: parent, source: "ab")

        let query = Query(patterns: [
            .nodeMatch(
                type: "list",
                children: [
                    .quantified(
                        pattern: .nodeMatch(type: "identifier", children: [], capture: "item"), quantifier: .oneOrMore)
                ],
                capture: nil
            )
        ])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        #expect(matches[0].captures.count == 2)
    }

    @Test
    func `Quantified oneOrMore fails with zero matches`() {
        let number = SyntaxNode(type: "number", byteRange: 0 ..< 1)
        let parent = SyntaxNode(type: "list", children: [number], byteRange: 0 ..< 1)
        let tree = SyntaxTree(root: parent, source: "1")

        let query = Query(patterns: [
            .nodeMatch(
                type: "list",
                children: [
                    .quantified(
                        pattern: .nodeMatch(type: "identifier", children: [], capture: "item"), quantifier: .oneOrMore)
                ],
                capture: nil
            )
        ])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.isEmpty)
    }

    @Test
    func `Quantified zeroOrMore matches zero children`() {
        let parent = SyntaxNode(type: "list", children: [], byteRange: 0 ..< 0)
        let tree = SyntaxTree(root: parent, source: "")

        let query = Query(patterns: [
            .nodeMatch(
                type: "list",
                children: [
                    .quantified(
                        pattern: .nodeMatch(type: "identifier", children: [], capture: "item"), quantifier: .zeroOrMore)
                ],
                capture: nil
            )
        ])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        #expect(matches[0].captures.isEmpty)
    }

    @Test
    func `Multiple captures produce both names`() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = try QueryParser.parse("(identifier) @var @name")
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        let captureNames = matches[0].captures.map(\.name)
        #expect(captureNames.contains("var"))
        #expect(captureNames.contains("name"))
    }

    @Test
    func `Matches come in pre-order, a node before its descendants and siblings left to right`() {
        let first = SyntaxNode(type: "leaf", byteRange: 0 ..< 1)
        let second = SyntaxNode(type: "leaf", byteRange: 1 ..< 2)
        let inner = SyntaxNode(type: "inner", children: [first, second], byteRange: 0 ..< 2)
        let last = SyntaxNode(type: "leaf", byteRange: 2 ..< 3)
        let root = SyntaxNode(type: "outer", children: [inner, last], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")

        let matches = QueryMatcher.execute(query: Query(patterns: [.wildcard(capture: "node")]), tree: tree)

        let visited = matches.compactMap { $0.captures.first?.node.byteRange }
        #expect(visited == [0 ..< 3, 0 ..< 2, 0 ..< 1, 1 ..< 2, 2 ..< 3])
    }

    @Test
    func `A point range skips the nodes outside it with their descendants`() {
        let before = SyntaxNode(
            type: "identifier", byteRange: 0 ..< 1, pointRange: Point(row: 0, column: 0) ..< Point(row: 0, column: 1))
        let hidden = SyntaxNode(
            type: "identifier", byteRange: 2 ..< 3, pointRange: Point(row: 1, column: 0) ..< Point(row: 1, column: 1))
        let block = SyntaxNode(
            type: "block", children: [hidden], byteRange: 2 ..< 3,
            pointRange: Point(row: 1, column: 0) ..< Point(row: 1, column: 1))
        let root = SyntaxNode(
            type: "source", children: [before, block], byteRange: 0 ..< 3,
            pointRange: Point(row: 0, column: 0) ..< Point(row: 1, column: 1))
        let tree = SyntaxTree(root: root, source: "a\nb")
        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "id")])

        let matches = QueryMatcher.execute(
            query: query, tree: tree, pointRange: Point(row: 0, column: 0) ..< Point(row: 0, column: 5))

        #expect(matches.compactMap { $0.captures.first?.node.byteRange } == [0 ..< 1])
    }

    @Test
    func `A query over a tree too deep to recurse into matches every node on a pool-sized stack`() async {
        // Recursing once per level overflows a 512 KiB stack near 2,000 levels.
        let summary = await onThread {
            let tree = Self.makeChain(depth: 50_000)
            return Self.summarizeMatches(in: tree)
        }
        #expect(summary.count == 50_000)
        #expect(summary.firstPattern == 0)
        #expect(summary.leafCapture == "leaf")
    }

    /// A `depth`-level chain of `branch` nodes ending in one `leaf`.
    private static func makeChain(depth: Int) -> SyntaxTree {
        var node = SyntaxNode(type: "leaf", byteRange: 0 ..< 1)
        for _ in 1 ..< depth {
            node = SyntaxNode(type: "branch", children: [node], byteRange: 0 ..< 1)
        }
        return SyntaxTree(root: node, source: "x")
    }

    /// The match count, the first match's pattern and the last match's capture for branches without a capture and a
    /// captured leaf; the matches are gone before the tree, so no capture outlives it.
    private static func summarizeMatches(
        in tree: SyntaxTree
    ) -> (count: Int, firstPattern: Int?, leafCapture: String?) {
        let query = Query(patterns: [
            .nodeMatch(type: "branch", children: [], capture: nil),
            .nodeMatch(type: "leaf", children: [], capture: "leaf")
        ])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        return (matches.count, matches.first?.patternIndex, matches.last?.captures.first?.name)
    }
}
