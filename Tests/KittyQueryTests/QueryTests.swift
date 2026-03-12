import Testing

@testable import KittyParser
@testable import KittyQuery

@Suite
struct QueryParserTests {
    @Test
    func `Parse simple node match`() throws {
        let query = try QueryParser.parse("(identifier) @var")
        #expect(query.patterns.count == 1)
        let (type, capture) = try requireNodeMatch(query.patterns[0])
        #expect(type == "identifier")
        #expect(capture == "var")
    }

    @Test
    func `Parse literal match`() throws {
        let query = try QueryParser.parse("\"if\" @keyword")
        #expect(query.patterns.count == 1)
        let (value, capture) = try requireLiteral(query.patterns[0])
        #expect(value == "if")
        #expect(capture == "keyword")
    }

    @Test
    func `Parse wildcard`() throws {
        let query = try QueryParser.parse("(_) @any")
        #expect(query.patterns.count == 1)
        #expect(try requireWildcard(query.patterns[0]) == "any")
    }

    @Test
    func `Parse multiple patterns`() throws {
        let source = """
            (function_declaration) @function
            (identifier) @variable
            """
        let query = try QueryParser.parse(source)
        #expect(query.patterns.count == 2)
    }

    @Test
    func `Parse with comment`() throws {
        let source = """
            ; This is a comment
            (identifier) @var
            """
        let query = try QueryParser.parse(source)
        #expect(query.patterns.count == 1)
    }

    @Test
    func `Parse parenthesized eq predicate`() throws {
        let query = try QueryParser.parse("(#eq? @var \"self\")")
        #expect(query.patterns.count == 1)

        let (capture, value) = try requireEqPredicate(query.patterns[0])
        #expect(capture == "@var")
        #expect(value == "self")
    }

    @Test
    func `Parse parenthesized match predicate`() throws {
        let query = try QueryParser.parse("(#match? @comment \"TODO\")")
        #expect(query.patterns.count == 1)

        let (capture, pattern) = try requireMatchPredicate(query.patterns[0])
        #expect(capture == "@comment")
        #expect(pattern == "TODO")
    }

    @Test
    func `Parse pattern with trailing parenthesized predicate`() throws {
        let query = try QueryParser.parse("(identifier) @var (#eq? @var \"self\")")
        #expect(query.patterns.count == 1)

        let patterns = try requireSequence(query.patterns[0])
        #expect(patterns.count == 2)
        let (type, capture) = try requireNodeMatch(patterns[0])
        #expect(type == "identifier")
        #expect(capture == "var")

        let (predicateCapture, value) = try requireEqPredicate(patterns[1])
        #expect(predicateCapture == "@var")
        #expect(value == "self")
    }

    @Test
    func `Parse tree-sitter directive as a no-op predicate`() throws {
        let query = try QueryParser.parse("(identifier) @name (#set! test.scope \"demo\")")
        #expect(query.patterns.count == 1)

        let patterns = try requireSequence(query.patterns[0])
        #expect(patterns.count == 2)
        let (name, arguments) = try requireDirectivePredicate(patterns[1])
        #expect(name == "#set!")
        #expect(arguments == ["test.scope", "demo"])
    }

    @Test
    func `Capture after alternation is applied to each alternative`() throws {
        let query = try QueryParser.parse("[(true) (false) (null)] @constant.builtin")
        #expect(query.patterns.count == 1)

        let alternatives = try requireAlternation(query.patterns[0])
        #expect(alternatives.count == 3)

        for alternative in alternatives {
            let (_, capture) = try requireNodeMatch(alternative)
            #expect(capture == "constant.builtin")
        }
    }

    @Test
    func `Parse anchor and quantifier syntax used by bundled highlight queries`() throws {
        let query = try QueryParser.parse("((identifier) @type . (identifier) @member)+")
        #expect(query.patterns.count == 1)
    }
}

@Suite
struct QueryMatcherTests {
    @Test
    func `Match node by type`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test
    func `Wildcard matches any node`() {
        let node = SyntaxNode(type: "anything", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")

        let query = Query(patterns: [.wildcard(capture: "any")])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.count >= 1)
    }

    @Test
    func `Match within byte range`() {
        let node1 = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let node2 = SyntaxNode(type: "identifier", byteRange: 10..<13)
        let root = SyntaxNode(type: "source", children: [node1, node2], byteRange: 0..<13)
        let tree = SyntaxTree(root: root, source: "abc       def")

        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])
        let matches = QueryMatcher.execute(query: query, tree: tree, byteRange: 0..<5)
        #expect(matches.count == 1)
    }

    @Test
    func `Parenthesized predicate filters a captured node match`() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<4)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<4)
        let tree = SyntaxTree(root: root, source: "self")

        let query = try QueryParser.parse("(identifier) @var (#eq? @var \"self\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.name == "var")
    }

    @Test
    func `Wildcard predicate filters wildcard matches`() throws {
        let comment = SyntaxNode(type: "comment", byteRange: 0..<4)
        let root = SyntaxNode(type: "source", children: [comment], byteRange: 0..<7)
        let tree = SyntaxTree(root: root, source: "TODO();")

        let query = try QueryParser.parse("(_) @comment (#match? @comment \"^TODO$\")")
        let matches = QueryMatcher.execute(query: query, tree: tree)

        #expect(matches.count == 1)
        #expect(matches[0].captures.first?.node == comment)
        #expect(matches[0].captures.first?.name == "comment")
    }

    @Test
    func `Positional child matching respects order`() {
        let identifier = SyntaxNode(type: "identifier", byteRange: 0..<1)
        let number = SyntaxNode(type: "number", byteRange: 1..<2)
        let matchingCall = SyntaxNode(
            type: "call", children: [identifier, number], byteRange: 0..<2)
        let reversedCall = SyntaxNode(
            type: "call", children: [number, identifier], byteRange: 0..<2)

        let query = Query(patterns: [
            .nodeMatch(
                type: "call",
                children: [
                    .nodeMatch(type: "identifier", children: [], capture: "first"),
                    .nodeMatch(type: "number", children: [], capture: "second"),
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
            )
        ])

        let matches = QueryMatcher.execute(query: query, tree: tree)
        #expect(matches.isEmpty)
    }
}

@Suite
struct PredicatesTests {
    @Test
    func `eq predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<4)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .eq(capture: "@var", value: "self"),
            captures: captures,
            source: "self"
        )
        #expect(result)
    }

    @Test
    func `not-eq predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .notEq(capture: "@var", value: "self"),
            captures: captures,
            source: "abc"
        )
        #expect(result)
    }

    @Test
    func `any-of predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<2)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "kw")]
        let result = Predicates.evaluate(
            .anyOf(capture: "@kw", values: ["if", "for", "while"]),
            captures: captures,
            source: "if"
        )
        #expect(result)
    }

    @Test
    func `directive predicate is a no-op`() {
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

@Suite
struct QueryCursorTests {
    @Test
    func `Iterate matches`() throws {
        let node = SyntaxNode(type: "identifier", byteRange: 0..<3)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<3)
        let tree = SyntaxTree(root: root, source: "abc")
        let query = Query(patterns: [.nodeMatch(type: "identifier", children: [], capture: "var")])

        var cursor = QueryCursor(query: query, tree: tree)
        let match = cursor.next()
        _ = try #require(match)
        #expect(cursor.next() == nil)
    }
}

private enum QueryPatternExpectationError: Error {
    case expectedAlternation
    case expectedDirectivePredicate
    case expectedEqPredicate
    case expectedLiteral
    case expectedMatchPredicate
    case expectedNodeMatch
    case expectedSequence
    case expectedWildcard
}

private func requireAlternation(_ pattern: QueryPattern) throws -> [QueryPattern] {
    guard case .alternation(let alternatives) = pattern else {
        throw QueryPatternExpectationError.expectedAlternation
    }
    return alternatives
}

private func requireDirectivePredicate(_ pattern: QueryPattern) throws -> (
    name: String, arguments: [String]
) {
    guard case .predicate(.directive(name: let name, arguments: let arguments)) = pattern else {
        throw QueryPatternExpectationError.expectedDirectivePredicate
    }
    return (name, arguments)
}

private func requireEqPredicate(_ pattern: QueryPattern) throws -> (capture: String, value: String)
{
    guard case .predicate(.eq(capture: let capture, value: let value)) = pattern else {
        throw QueryPatternExpectationError.expectedEqPredicate
    }
    return (capture, value)
}

private func requireLiteral(_ pattern: QueryPattern) throws -> (value: String, capture: String?) {
    guard case .literal(let value, let capture) = pattern else {
        throw QueryPatternExpectationError.expectedLiteral
    }
    return (value, capture)
}

private func requireMatchPredicate(_ pattern: QueryPattern) throws -> (
    capture: String, pattern: String
) {
    guard case .predicate(.match(capture: let capture, pattern: let matchedPattern)) = pattern
    else {
        throw QueryPatternExpectationError.expectedMatchPredicate
    }
    return (capture, matchedPattern)
}

private func requireNodeMatch(_ pattern: QueryPattern) throws -> (type: String, capture: String?) {
    guard case .nodeMatch(let type, _, let capture) = pattern else {
        throw QueryPatternExpectationError.expectedNodeMatch
    }
    return (type, capture)
}

private func requireSequence(_ pattern: QueryPattern) throws -> [QueryPattern] {
    guard case .sequence(let patterns) = pattern else {
        throw QueryPatternExpectationError.expectedSequence
    }
    return patterns
}

private func requireWildcard(_ pattern: QueryPattern) throws -> String? {
    guard case .wildcard(let capture) = pattern else {
        throw QueryPatternExpectationError.expectedWildcard
    }
    return capture
}
