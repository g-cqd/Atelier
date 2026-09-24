import Testing

@testable import AtelierParser
@testable import AtelierQuery

/// The matcher tries at each node only the patterns whose root can match the node's type, and finds exactly the matches
/// it found trying every pattern.
struct PatternIndexTests {
    /// `f(x, "s") ; y`: a call with a named field, arguments, anonymous punctuation and a trailing identifier.
    private static let tree: SyntaxTree = {
        let name = SyntaxNode(type: "identifier", byteRange: 0 ..< 1)
        let open = SyntaxNode(type: "(", byteRange: 1 ..< 2, isNamed: false)
        let argument = SyntaxNode(type: "identifier", byteRange: 2 ..< 3)
        let comma = SyntaxNode(type: ",", byteRange: 3 ..< 4, isNamed: false)
        let string = SyntaxNode(type: "string", byteRange: 5 ..< 8)
        let close = SyntaxNode(type: ")", byteRange: 8 ..< 9, isNamed: false)
        let arguments = SyntaxNode(
            type: "arguments", children: [open, argument, comma, string, close], byteRange: 1 ..< 9)
        let call = SyntaxNode(
            type: "call", children: [name, arguments], byteRange: 0 ..< 9,
            fields: ["function": [name], "arguments": [arguments]])
        let semicolon = SyntaxNode(type: ";", byteRange: 10 ..< 11, isNamed: false)
        let trailing = SyntaxNode(type: "identifier", byteRange: 12 ..< 13)
        let root = SyntaxNode(type: "program", children: [call, semicolon, trailing], byteRange: 0 ..< 13)
        return SyntaxTree(root: root, source: #"f(x, "s") ; y"#)
    }()

    @Test
    func `indexed matching gives the matches of trying every pattern, in the same order`() throws {
        let query = try QueryParser.parse(
            """
            (identifier) @variable
            (call function: (identifier) @function) @call
            [(string) (identifier)] @value
            ["(" ")"] @bracket
            "," @delimiter
            (_) @node
            (identifier) @self (#eq? @self "y")
            (arguments (identifier) @argument+)
            (arguments (string) @maybe?)
            ";" @end
            (call !body) @bodiless
            [(string) "x"] @mixed
            """)
        let indexed = QueryMatcher.execute(query: query, tree: Self.tree)
        #expect(indexed == QueryMatcher.executeTryingEveryPattern(query: query, tree: Self.tree))
        #expect(indexed.count > 20)
    }

    @Test
    func `a pattern is a candidate only at the types its root can match`() throws {
        let query = try QueryParser.parse(
            """
            (identifier) @a
            [(string) (number)] @b
            "," @c
            (_) @d
            (call) @e (#eq? @e "f")
            [(string) "x"] @f
            (identifier) @g?
            """)
        #expect(query.candidatePatterns(forType: "identifier") == [0, 2, 3, 5, 6])
        #expect(query.candidatePatterns(forType: "string") == [1, 2, 3, 5, 6])
        #expect(query.candidatePatterns(forType: "call") == [2, 3, 4, 5, 6])
        #expect(query.candidatePatterns(forType: "comment") == [2, 3, 5, 6])
    }
}
