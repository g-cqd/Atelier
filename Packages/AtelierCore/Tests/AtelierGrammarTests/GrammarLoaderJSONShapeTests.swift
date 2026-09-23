import Foundation
import Testing

@testable import AtelierGrammar

/// How `GrammarLoader` reads the shape of grammar.json: encoding, repeated keys, member types and nesting.
@Suite
struct GrammarLoaderJSONShapeTests {
    @Test
    func `every rule type and top-level member reads into its value`() throws {
        let json = #"""
            {
                "name": "all",
                "rules": {
                    "r": {"type": "SEQ", "members": [
                        {"type": "SYMBOL", "name": "s"},
                        {"type": "STRING", "value": "lit"},
                        {"type": "PATTERN", "value": "[a-z]+"},
                        {"type": "CHOICE", "members": [{"type": "BLANK"}]},
                        {"type": "REPEAT", "content": {"type": "BLANK"}},
                        {"type": "REPEAT1", "content": {"type": "BLANK"}},
                        {"type": "OPTIONAL", "content": {"type": "BLANK"}},
                        {"type": "PREC", "value": 1, "content": {"type": "BLANK"}},
                        {"type": "PREC_LEFT", "value": -2, "content": {"type": "BLANK"}},
                        {"type": "PREC_RIGHT", "value": 3, "content": {"type": "BLANK"}},
                        {"type": "PREC_DYNAMIC", "value": 4, "content": {"type": "BLANK"}},
                        {"type": "TOKEN", "content": {"type": "BLANK"}},
                        {"type": "IMMEDIATE_TOKEN", "content": {"type": "BLANK"}},
                        {"type": "FIELD", "name": "f", "content": {"type": "BLANK"}},
                        {"type": "ALIAS", "content": {"type": "BLANK"}, "value": "a", "named": true}
                    ]}
                },
                "extras": [{"type": "PATTERN", "value": "\\s"}],
                "conflicts": [["a", "b"]],
                "externals": [{"type": "SYMBOL", "name": "ext"}],
                "inline": ["i"],
                "word": "w",
                "supertypes": ["st"],
                "precedences": [["p", {"type": "STRING", "value": "+"}, {"type": "SYMBOL", "name": "q"}]]
            }
            """#
        let expected = GrammarDefinition(
            name: "all",
            rules: [
                (
                    name: "r",
                    rule: .seq([
                        .symbol("s"), .string("lit"), .pattern("[a-z]+"), .choice([.blank]), .repeat(.blank),
                        .repeat1(.blank), .optional(.blank), .prec(1, .blank), .precLeft(-2, .blank),
                        .precRight(3, .blank), .precDynamic(4, .blank), .token(.blank), .immediateToken(.blank),
                        .field("f", .blank), .alias(.blank, "a", true)
                    ])
                )
            ],
            extras: [.pattern("\\s")],
            conflicts: [["a", "b"]],
            externals: [.symbol("ext")],
            inline: ["i"],
            word: "w",
            supertypes: ["st"],
            precedences: [[.symbol("p"), .literal("+"), .symbol("q")]]
        )

        #expect(try GrammarLoader.parse(Data(json.utf8)) == expected)
    }

    @Test
    func `a leading byte-order mark is skipped`() throws {
        let json = Data(#"{"name": "bom", "rules": {"r": {"type": "BLANK"}}}"#.utf8)

        let grammar = try GrammarLoader.parse(Data([0xEF, 0xBB, 0xBF]) + json)

        #expect(grammar == (try GrammarLoader.parse(json)))
    }

    @Test
    func `rules keep document order and a repeated rule name keeps its first definition`() throws {
        let grammar = try GrammarLoader.parse(
            grammar(
                rules: #"""
                    "b": {"type": "STRING", "value": "1"},
                    "a": {"type": "STRING", "value": "2"},
                    "b": {"type": "STRING", "value": "3"}
                    """#))

        #expect(grammar.rules.map(\.name) == ["b", "a"])
        #expect(grammar.rules.map(\.rule) == [.string("1"), .string("2")])
    }

    @Test
    func `a repeated key keeps its first value at the top level and in a rule`() throws {
        let json = #"""
            {
                "name": "first",
                "word": "w1",
                "rules": {"r": {"type": "STRING", "value": "first", "value": "second"}},
                "name": "second",
                "word": "w2"
            }
            """#

        let grammar = try GrammarLoader.parse(Data(json.utf8))

        #expect(grammar.name == "first")
        #expect(grammar.word == "w1")
        #expect(grammar.rules.map(\.rule) == [.string("first")])
    }

    @Test
    func `an escaped rule name reads decoded`() throws {
        let grammar = try GrammarLoader.parse(grammar(rules: #""a\u0062": {"type": "BLANK"}"#))

        #expect(grammar.rules.map(\.name) == ["ab"])
    }

    @Test(arguments: ["[]", "\"g\"", "1", "null"])
    func `a root that is not an object is invalid JSON`(root: String) {
        #expect(throws: GrammarError.invalidJSON("Root must be an object")) {
            try GrammarLoader.parse(Data(root.utf8))
        }
    }

    @Test(arguments: ["[]", "null", "\"rules\"", "1"])
    func `a rules member that is not an object is invalid JSON`(rules: String) {
        #expect(throws: GrammarError.invalidJSON("Expected object for 'rules'")) {
            try GrammarLoader.parse(Data(#"{"name": "g", "rules": \#(rules)}"#.utf8))
        }
    }

    @Test
    func `a grammar without rules reports the missing field`() {
        #expect(throws: GrammarError.missingField("rules")) {
            try GrammarLoader.parse(Data(#"{"name": "g"}"#.utf8))
        }
    }

    @Test
    func `empty input is invalid JSON`() {
        let error = #expect(throws: GrammarError.self) { try GrammarLoader.parse(Data()) }
        #expect(error?.isInvalidJSON == true)
    }

    @Test(arguments: [
        ("[]", "array"), ("\"SYMBOL\"", "string"), ("1", "number"), ("true", "boolean"), ("null", "null")
    ])
    func `a rule that is not an object is an invalid rule type`(rule: String, kind: String) {
        #expect(throws: GrammarError.invalidRuleType("Expected object, got \(kind)")) {
            try GrammarLoader.parse(grammar(rules: #""r": \#(rule)"#))
        }
    }

    @Test
    func `a rule without a type or with an unknown one is rejected`() {
        #expect(throws: GrammarError.missingField("type in rule")) {
            try GrammarLoader.parse(grammar(rules: #""r": {"name": "x"}"#))
        }
        #expect(throws: GrammarError.invalidRuleType("NOPE")) {
            try GrammarLoader.parse(grammar(rules: #""r": {"type": "NOPE"}"#))
        }
    }

    @Test(arguments: [("1", 1), ("-2", -2), ("1.0", 1), ("1e2", 100), ("true", 1), ("false", 0)])
    func `a precedence value reads an integral number or a boolean`(value: String, expected: Int) throws {
        let grammar = try GrammarLoader.parse(
            grammar(rules: #""r": {"type": "PREC", "value": \#(value), "content": {"type": "BLANK"}}"#))

        #expect(grammar.rules.map(\.rule) == [.prec(expected, .blank)])
    }

    @Test(arguments: ["1.5", "null", "[1]"])
    func `a precedence value that is neither an integer nor a name is reported missing`(value: String) {
        #expect(throws: GrammarError.missingField("value")) {
            try GrammarLoader.parse(
                grammar(rules: #""r": {"type": "PREC", "value": \#(value), "content": {"type": "BLANK"}}"#))
        }
    }

    @Test(arguments: [
        (#", "named": true"#, true), (#", "named": 1"#, true), (#", "named": 1.0"#, true),
        (#", "named": false"#, false), (#", "named": 0"#, false), (#", "named": 2"#, false),
        (#", "named": "true""#, false), (#", "named": null"#, false), ("", false)
    ])
    func `an alias is named by a boolean or by 1 or 0`(named: String, expected: Bool) throws {
        let grammar = try GrammarLoader.parse(
            grammar(rules: #""r": {"type": "ALIAS", "content": {"type": "BLANK"}, "value": "a"\#(named)}"#))

        #expect(grammar.rules.map(\.rule) == [.alias(.blank, "a", expected)])
    }

    @Test
    func `top-level members of the wrong shape read as empty`() throws {
        let json = #"""
            {
                "name": "g",
                "rules": {"r": {"type": "BLANK"}},
                "extras": {"type": "BLANK"},
                "conflicts": [["a"], ["b", 1]],
                "externals": null,
                "inline": ["i", null],
                "word": 1,
                "supertypes": "s",
                "precedences": [["p"], "q"]
            }
            """#

        let grammar = try GrammarLoader.parse(Data(json.utf8))

        #expect(grammar.extras.isEmpty)
        #expect(grammar.conflicts.isEmpty)
        #expect(grammar.externals.isEmpty)
        #expect(grammar.inline.isEmpty)
        #expect(grammar.word == nil)
        #expect(grammar.supertypes.isEmpty)
        #expect(grammar.precedences.isEmpty)
    }

    @Test
    func `extras must hold rules`() {
        #expect(throws: GrammarError.invalidRuleType("Expected object, got number")) {
            try GrammarLoader.parse(Data(#"{"name": "g", "rules": {}, "extras": [1]}"#.utf8))
        }
    }

    @Test(arguments: ["1", "null", #"{"type": "PATTERN", "value": "x"}"#, #"{"type": "STRING"}"#])
    func `a precedence entry must be a name or a string or symbol rule`(entry: String) {
        #expect(throws: GrammarError.invalidRuleType("Invalid precedence entry")) {
            try GrammarLoader.parse(Data(#"{"name": "g", "rules": {}, "precedences": [[\#(entry)]]}"#.utf8))
        }
    }

    @Test
    func `nesting at the depth limit loads and one level deeper is invalid JSON`() throws {
        let atLimit = try GrammarLoader.parse(nestedGrammar(depth: GrammarLoader.maxNestingDepth))
        #expect(atLimit.rules.count == 1)

        let error = #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(nestedGrammar(depth: GrammarLoader.maxNestingDepth + 1))
        }
        #expect(error?.isInvalidJSON == true)
    }

    private func grammar(rules: String) -> Data {
        Data(#"{"name": "g", "rules": {\#(rules)}}"#.utf8)
    }

    /// A grammar whose deepest container sits `depth` levels down: the root and `rules` take two levels, and each
    /// `REPEAT` rule nests its content one level deeper, down to a `BLANK` rule.
    private func nestedGrammar(depth: Int) -> Data {
        let repeats = depth - 3
        let rule =
            String(repeating: #"{"type": "REPEAT", "content": "#, count: repeats) + #"{"type": "BLANK"}"#
            + String(repeating: "}", count: repeats)
        return Data(#"{"name": "deep", "rules": {"r": \#(rule)}}"#.utf8)
    }
}

extension GrammarError {
    fileprivate var isInvalidJSON: Bool {
        guard case .invalidJSON = self else { return false }
        return true
    }
}
