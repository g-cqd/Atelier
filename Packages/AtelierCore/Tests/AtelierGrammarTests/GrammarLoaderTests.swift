import Foundation
import Testing

@testable import AtelierGrammar

@Suite
struct GrammarLoaderTests {
    @Test
    func `Parse minimal JSON grammar`() throws {
        let json = """
            {
                "name": "test",
                "rules": {
                    "source": {
                        "type": "REPEAT",
                        "content": {
                            "type": "SYMBOL",
                            "name": "statement"
                        }
                    },
                    "statement": {
                        "type": "STRING",
                        "value": "hello"
                    }
                },
                "extras": [],
                "conflicts": [],
                "externals": [],
                "inline": [],
                "supertypes": []
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        #expect(grammar.name == "test")
        #expect(grammar.rules.count == 2)
    }

    @Test
    func `Preserves JSON rule order for start symbol`() throws {
        let json = """
            {
                "name": "ordering",
                "rules": {
                    "z_entry": {
                        "type": "SYMBOL",
                        "name": "statement"
                    },
                    "a_helper": {
                        "type": "STRING",
                        "value": "helper"
                    },
                    "statement": {
                        "type": "STRING",
                        "value": "stmt"
                    }
                }
            }
            """

        let grammar = try GrammarLoader.parse(Data(json.utf8))
        #expect(grammar.rules.map(\.name) == ["z_entry", "a_helper", "statement"])

        let result = try ParseTableCompiler.compile(grammar)
        let startRule = try #require(result.productions.first)
        #expect(startRule.name == "_start")
        #expect(startRule.symbols == ["z_entry"])
    }

    @Test
    func `Parse grammar with all rule types`() throws {
        let json = """
            {
                "name": "complex",
                "rules": {
                    "program": {
                        "type": "SEQ",
                        "members": [
                            {"type": "STRING", "value": "start"},
                            {"type": "CHOICE", "members": [
                                {"type": "SYMBOL", "name": "expr"},
                                {"type": "BLANK"}
                            ]},
                            {"type": "REPEAT", "content": {"type": "SYMBOL", "name": "stmt"}},
                            {"type": "PREC_LEFT", "value": 1, "content": {"type": "SYMBOL", "name": "expr"}}
                        ]
                    },
                    "expr": {"type": "PATTERN", "value": "[0-9]+"},
                    "stmt": {"type": "SYMBOL", "name": "expr"}
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        #expect(grammar.name == "complex")
    }

    @Test
    func `Missing name throws error`() {
        let json = """
            {"rules": {}}
            """
        #expect(throws: GrammarError.missingField("name")) {
            try GrammarLoader.parse(Data(json.utf8))
        }
    }

    @Test
    func `Invalid JSON throws error`() {
        #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(Data("not json".utf8))
        }
    }

    @Test
    func `Parses surrogate-pair unicode escapes in JSON strings`() throws {
        let json = #"""
            {
                "name": "emoji",
                "rules": {
                    "source": {
                        "type": "STRING",
                        "value": "\uD83D\uDE00"
                    }
                }
            }
            """#

        let grammar = try GrammarLoader.parse(Data(json.utf8))
        #expect(grammar.rules.count == 1)
        #expect(try requireStringRule(grammar.rules.first?.rule) == "😀")
    }
}
