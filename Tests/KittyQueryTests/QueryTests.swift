import Testing
@testable import KittyQuery
@testable import KittyParser

@Suite("QueryParser")
struct QueryParserTests {
    @Test("Parse simple node match")
    func simpleNodeMatch() throws {
        let query = try QueryParser.parse("(identifier) @var")
        #expect(query.patterns.count == 1)
        if case .nodeMatch(let type, _, let capture) = query.patterns[0] {
            #expect(type == "identifier")
            #expect(capture == "var")
        } else {
            Issue.record("Expected node match")
        }
    }

    @Test("Parse literal match")
    func literalMatch() throws {
        let query = try QueryParser.parse("\"if\" @keyword")
        #expect(query.patterns.count == 1)
        if case .literal(let value, let capture) = query.patterns[0] {
            #expect(value == "if")
            #expect(capture == "keyword")
        } else {
            Issue.record("Expected literal match")
        }
    }

    @Test("Parse wildcard")
    func wildcard() throws {
        let query = try QueryParser.parse("(_) @any")
        #expect(query.patterns.count == 1)
        if case .wildcard(let capture) = query.patterns[0] {
            #expect(capture == "any")
        } else {
            Issue.record("Expected wildcard")
        }
    }

    @Test("Parse multiple patterns")
    func multiplePatterns() throws {
        let source = """
        (function_declaration) @function
        (identifier) @variable
        """
        let query = try QueryParser.parse(source)
        #expect(query.patterns.count == 2)
    }

    @Test("Parse with comment")
    func withComment() throws {
        let source = """
        ; This is a comment
        (identifier) @var
        """
        let query = try QueryParser.parse(source)
        #expect(query.patterns.count == 1)
    }
}

@Suite("QueryMatcher")
struct QueryMatcherTests {
    @Test("Match node by type")
    func matchByType() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test("Wildcard matches any node")
    func wildcardMatch() {
        let node = SyntaxNode(type: "anything", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.wildcard(capture: "any")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count >= 1)
    }

    @Test("Match within byte range")
    func matchInRange() {
        let node1 = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let node2 = SyntaxNode(type: "identifier", byteRange: 10..<13)
        let root = SyntaxNode(type: "source", children: [node1, node2], byteRange: 0..<13)
        let tree = SyntaxTree(root: root, source: "abc       def")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree, byteRange: 0..<5)
        #expect(matches.count == 1)
    }
}

@Suite("Predicates")
struct PredicatesTests {
    @Test("eq? predicate")
    func eqPredicate() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<4)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .eq(capture: "@var", value: "self"),
            captures: captures,
            source: "self"
        )
        #expect(result)
    }

    @Test("not-eq? predicate")
    func notEqPredicate() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .notEq(capture: "@var", value: "self"),
            captures: captures,
            source: "abc"
        )
        #expect(result)
    }

    @Test("any-of? predicate")
    func anyOfPredicate() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<2)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "kw")]
        let result = Predicates.evaluate(
            .anyOf(capture: "@kw", values: ["if", "for", "while"]),
            captures: captures,
            source: "if"
        )
        #expect(result)
    }
}

@Suite("QueryCursor")
struct QueryCursorTests {
    @Test("Iterate matches")
    func iterateMatches() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")
        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])

        var cursor = QueryCursor(query: query, tree: tree)
        let match = cursor.next()
        #expect(match != nil)
        #expect(cursor.next() == nil)
    }
}
