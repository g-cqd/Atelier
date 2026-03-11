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

    @Test("Parse parenthesized eq? predicate")
    func parenthesizedEqPredicate() throws {
        let query = try QueryParser.parse("(#eq? @var \"self\")")
        #expect(query.patterns.count == 1)

        if case .predicate(.eq(capture: let capture, value: let value)) = query.patterns[0] {
            #expect(capture == "@var")
            #expect(value == "self")
        } else {
            Issue.record("Expected eq? predicate")
        }
    }

    @Test("Parse parenthesized match? predicate")
    func parenthesizedMatchPredicate() throws {
        let query = try QueryParser.parse("(#match? @comment \"TODO\")")
        #expect(query.patterns.count == 1)

        if case .predicate(.match(capture: let capture, pattern: let pattern)) = query.patterns[0] {
            #expect(capture == "@comment")
            #expect(pattern == "TODO")
        } else {
            Issue.record("Expected match? predicate")
        }
    }

    @Test("Parse pattern with trailing parenthesized predicate")
    func trailingParenthesizedPredicate() throws {
        let query = try QueryParser.parse("(identifier) @var (#eq? @var \"self\")")
        #expect(query.patterns.count == 1)

        guard case .sequence(let patterns) = query.patterns[0] else {
            Issue.record("Expected sequence")
            return
        }

        #expect(patterns.count == 2)
        if case .nodeMatch(let type, _, let capture) = patterns[0] {
            #expect(type == "identifier")
            #expect(capture == "var")
        } else {
            Issue.record("Expected node match")
        }

        if case .predicate(.eq(capture: let predicateCapture, value: let value)) = patterns[1] {
            #expect(predicateCapture == "@var")
            #expect(value == "self")
        } else {
            Issue.record("Expected eq? predicate")
        }
    }

    @Test("Parse tree-sitter directive as a no-op predicate")
    func directivePredicate() throws {
        let query = try QueryParser.parse("(identifier) @name (#set! test.scope \"demo\")")
        #expect(query.patterns.count == 1)

        guard case .sequence(let patterns) = query.patterns[0] else {
            Issue.record("Expected sequence")
            return
        }

        #expect(patterns.count == 2)
        if case .predicate(.directive(name: let name, arguments: let arguments)) = patterns[1] {
            #expect(name == "#set!")
            #expect(arguments == ["test.scope", "demo"])
        } else {
            Issue.record("Expected directive predicate")
        }
    }

    @Test("Capture after alternation is applied to each alternative")
    func alternationCapture() throws {
        let query = try QueryParser.parse("[(true) (false) (null)] @constant.builtin")
        #expect(query.patterns.count == 1)

        guard case .alternation(let alternatives) = query.patterns[0] else {
            Issue.record("Expected alternation")
            return
        }

        #expect(alternatives.count == 3)

        for alternative in alternatives {
            guard case .nodeMatch(_, _, let capture) = alternative else {
                Issue.record("Expected node match alternative")
                return
            }
            #expect(capture == "constant.builtin")
        }
    }

    @Test("Parse anchor and quantifier syntax used by bundled highlight queries")
    func anchorAndQuantifierSyntax() throws {
        let query = try QueryParser.parse("((identifier) @type . (identifier) @member)+")
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

    @Test("Parenthesized predicate filters a captured node match")
    func parenthesizedPredicateMatch() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<4)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<4)
        let tree = SyntaxTree(root: root, source: "self")

        let query = try QueryParser.parse("(identifier) @var (#eq? @var \"self\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test("Wildcard predicate filters wildcard matches")
    func wildcardPredicateMatch() throws {
        let comment = SyntaxNode(type: "comment", byteRange: 0..<4)
        let root = SyntaxNode(type: "source", children: [comment], byteRange: 0..<7)
        let tree = SyntaxTree(root: root, source: "TODO();")

        let query = try QueryParser.parse("(_) @comment (#match? @comment \"^TODO$\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.node == comment)
        #expect(matches[0].captures.first?.name == "comment")
    }

    @Test("Positional child matching respects order")
    func positionalChildMatchingOrder() {
        let identifier = SyntaxNode(type: "identifier", byteRange: 0..<1)
        let number = SyntaxNode(type: "number", byteRange: 1..<2)
        let matchingCall = SyntaxNode(type: "call", children: [identifier, number], byteRange: 0..<2)
        let reversedCall = SyntaxNode(type: "call", children: [number, identifier], byteRange: 0..<2)

        let query = Query(patterns: [
            .nodeMatch(
                type: "call",
                children: [
                    .nodeMatch(type: "identifier", children: [], capture: "first"),
                    .nodeMatch(type: "number", children: [], capture: "second"),
                ],
                capture: nil
            ),
        ])

        let matchingTree = SyntaxTree(root: matchingCall, source: "ab")
        let reversedTree = SyntaxTree(root: reversedCall, source: "ab")

        let matchingResults = QueryMatcher.execute(query: query, tree: matchingTree)
        let reversedResults = QueryMatcher.execute(query: query, tree: reversedTree)

        #expect(matchingResults.count == 1)
        #expect(matchingResults[0].captures.map(\.name) == ["first", "second"])
        #expect(reversedResults.isEmpty)
    }

    @Test("Positional child matching does not reuse the same child")
    func positionalChildMatchingNoReuse() {
        let identifier = SyntaxNode(type: "identifier", byteRange: 0..<1)
        let call = SyntaxNode(type: "call", children: [identifier], byteRange: 0..<1)
        let tree = SyntaxTree(root: call, source: "a")

        let query = Query(patterns: [
            .nodeMatch(
                type: "call",
                children: [
                    .nodeMatch(type: "identifier", children: [], capture: "first"),
                    .nodeMatch(type: "identifier", children: [], capture: "second"),
                ],
                capture: nil
            ),
        ])

        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.isEmpty)
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

    @Test("directive predicate is a no-op")
    func directivePredicate() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<2)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "kw")]
        let result = Predicates.evaluate(
            .directive(name: "#set!", arguments: ["scope", "demo"]),
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
