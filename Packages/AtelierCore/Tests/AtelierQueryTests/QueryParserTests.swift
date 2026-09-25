import Testing

@testable import AtelierParser
@testable import AtelierQuery

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
        let query = try QueryParser.parse("_ @any")
        #expect(query.patterns.count == 1)
        #expect(try requireWildcard(query.patterns[0]) == "any")
    }

    @Test
    func `A parenthesized wildcard is a named wildcard node`() throws {
        let query = try QueryParser.parse("(_) @named")
        #expect(query.patterns == [.nodeMatch(type: QueryPattern.namedWildcardType, children: [], capture: "named")])
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
        let query = try QueryParser.parse("(#match? @comment \"NOTE\")")
        #expect(query.patterns.count == 1)

        let (capture, pattern) = try requireMatchPredicate(query.patterns[0])
        #expect(capture == "@comment")
        #expect(pattern == "NOTE")
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
    func `is-not? reads a lone property name as tree-sitter does`() throws {
        let query = try QueryParser.parse("((identifier) @function.builtin (#is-not? local))")
        let parts = try requireSequence(try #require(query.patterns.first))
        #expect(parts.last == .predicate(.isNot(capture: nil, property: "local", value: nil)))
    }

    @Test
    func `is? reads a capture in any position and a value`() throws {
        let query = try QueryParser.parse("((identifier) @id (#is? named @id) (#is-not? @id key value))")
        let parts = try requireSequence(try #require(query.patterns.first))
        #expect(parts[1] == .predicate(.is(capture: "@id", property: "named", value: nil)))
        #expect(parts[2] == .predicate(.isNot(capture: "@id", property: "key", value: "value")))
    }

    @Test
    func `A quoted argument that starts with @ is a string, not a capture`() throws {
        let query = try QueryParser.parse(#"((identifier) @id (#is-not? "@id" local))"#)
        let parts = try requireSequence(try #require(query.patterns.first))
        #expect(parts.last == .predicate(.isNot(capture: nil, property: "@id", value: "local")))
    }

    @Test
    func `A text predicate whose first argument is a quoted string is an error`() {
        #expect(throws: QueryError.self) { try QueryParser.parse(#"((identifier) @id (#eq? "@id" "self"))"#) }
        #expect(throws: QueryError.self) { try QueryParser.parse(#"((identifier) @id (#match? "@id" "^s"))"#) }
    }

    @Test
    func `is-not? without a property name or with four arguments is an error`() {
        #expect(throws: QueryError.self) { try QueryParser.parse("((identifier) @id (#is-not? @id))") }
        #expect(throws: QueryError.self) { try QueryParser.parse("((identifier) @id (#is-not? @id a b c))") }
    }

    @Test
    func `A wildcard node reads its children and fields`() throws {
        let query = try QueryParser.parse("(flow_mapping (_ key: (flow_node) @property (plain_scalar)) @pair)")
        guard case .nodeMatch("flow_mapping", let children, nil) = try #require(query.patterns.first) else {
            throw QueryPatternExpectationError.expectedNodeMatch
        }
        #expect(
            children == [
                .nodeMatch(
                    type: QueryPattern.namedWildcardType,
                    children: [
                        .fieldMatch(
                            name: "key", pattern: .nodeMatch(type: "flow_node", children: [], capture: "property")),
                        .nodeMatch(type: "plain_scalar", children: [], capture: nil)
                    ],
                    capture: "pair")
            ])
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

    @Test
    func `Parse quantifier plus`() throws {
        let query = try QueryParser.parse("(identifier)+")
        #expect(query.patterns.count == 1)
        if case .quantified(let inner, let quantifier) = query.patterns[0] {
            #expect(quantifier == .oneOrMore)
            let (type, _) = try requireNodeMatch(inner)
            #expect(type == "identifier")
        } else {
            Issue.record("Expected .quantified pattern")
        }
    }

    @Test
    func `A capture after a quantifier captures the repeated node`() throws {
        let query = try QueryParser.parse(#"(annotation "@" @attribute (use_site_target)? @attribute)"#)
        guard case .nodeMatch("annotation", let children, nil) = try #require(query.patterns.first) else {
            throw QueryPatternExpectationError.expectedNodeMatch
        }
        #expect(
            children == [
                .literal("@", capture: "attribute"),
                .quantified(
                    pattern: .nodeMatch(type: "use_site_target", children: [], capture: "attribute"),
                    quantifier: .optional)
            ])
    }

    @Test
    func `Quantifiers on one pattern join as tree-sitter joins them`() throws {
        let optionalTwice = try requireQuantified(try #require(try QueryParser.parse("(a)? @x ?").patterns.first))
        let optionalThenPlus = try requireQuantified(try #require(try QueryParser.parse("(a)?+").patterns.first))
        #expect(optionalTwice.quantifier == .optional)
        #expect(optionalThenPlus.quantifier == .zeroOrMore)
    }

    @Test
    func `Parse quantifier star`() throws {
        let query = try QueryParser.parse("(identifier)*")
        #expect(query.patterns.count == 1)
        if case .quantified(_, let quantifier) = query.patterns[0] {
            #expect(quantifier == .zeroOrMore)
        } else {
            Issue.record("Expected .quantified pattern")
        }
    }

    @Test
    func `Parse quantifier optional`() throws {
        let query = try QueryParser.parse("(identifier)?")
        #expect(query.patterns.count == 1)
        if case .quantified(_, let quantifier) = query.patterns[0] {
            #expect(quantifier == .optional)
        } else {
            Issue.record("Expected .quantified pattern")
        }
    }

    @Test
    func `Parse multiple captures on same node`() throws {
        let query = try QueryParser.parse("(identifier) @var @name")
        #expect(query.patterns.count == 1)
        // Should produce a sequence that captures the same node under both names
        let patterns = try requireSequence(query.patterns[0])
        #expect(patterns.count == 2)
    }
}
