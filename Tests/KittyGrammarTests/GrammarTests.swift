import Testing
import Foundation
@testable import KittyGrammar

@Suite("GrammarDefinition")
struct GrammarDefinitionTests {
    @Test("Rule enum variants")
    func ruleVariants() {
        let sym = Rule.symbol("identifier")
        let str = Rule.string("if")
        let blank = Rule.blank
        #expect(sym == .symbol("identifier"))
        #expect(str == .string("if"))
        #expect(blank == .blank)
    }
}

@Suite("GrammarLoader")
struct GrammarLoaderTests {
    @Test("Parse minimal JSON grammar")
    func parseMinimal() throws {
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

    @Test("Parse grammar with all rule types")
    func parseAllRuleTypes() throws {
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

    @Test("Missing name throws error")
    func missingName() {
        let json = """
        {"rules": {}}
        """
        #expect(throws: GrammarError.missingField("name")) {
            try GrammarLoader.parse(Data(json.utf8))
        }
    }

    @Test("Invalid JSON throws error")
    func invalidJSON() {
        #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(Data("not json".utf8))
        }
    }
}

@Suite("ItemSet")
struct ItemSetTests {
    @Test("Basic closure")
    func basicClosure() {
        // S -> . E, E -> . "a"
        let productions: [(name: String, symbols: [String])] = [
            ("S'", ["S"]),
            ("S", ["E"]),
            ("E", ["\"a\""])
        ]
        let firstSets: [String: Set<String>] = [
            "S'": ["\"a\""],
            "S": ["\"a\""],
            "E": ["\"a\""],
            "\"a\"": ["\"a\""],
            "$end": ["$end"]
        ]
        let rulesByNT: [String: [Int]] = ["S'": [0], "S": [1], "E": [2]]

        let initial = ItemSet(items: [LRItem(ruleIndex: 0, dotPosition: 0, lookahead: "$end")])
        let closed = initial.closure(productions: productions, firstSets: firstSets, rulesByNonTerminal: rulesByNT)

        // Should contain items for S and E productions
        #expect(closed.items.count > 1)
    }
}

@Suite("ParseTableCompiler")
struct ParseTableCompilerTests {
    @Test("Compile simple grammar")
    func compileSimple() throws {
        let json = """
        {
            "name": "simple",
            "rules": {
                "source": {
                    "type": "STRING",
                    "value": "hello"
                }
            }
        }
        """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)
        #expect(result.parseTable.stateCount > 0)
        #expect(result.productions.count > 0)
    }
}

@Suite("LexTableCompiler")
struct LexTableCompilerTests {
    @Test("Extract keywords from grammar")
    func extractKeywords() throws {
        let json = """
        {
            "name": "kw_test",
            "rules": {
                "source": {
                    "type": "CHOICE",
                    "members": [
                        {"type": "STRING", "value": "if"},
                        {"type": "STRING", "value": "else"},
                        {"type": "STRING", "value": "while"}
                    ]
                }
            }
        }
        """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.keywords.count == 3)
        #expect(lexTable.keywords["if"] != nil)
        #expect(lexTable.keywords["else"] != nil)
        #expect(lexTable.keywords["while"] != nil)
    }
}

@Suite("KeywordExtractor")
struct KeywordExtractorTests {
    @Test("Extracts word-like keywords")
    func extractWords() throws {
        let json = """
        {
            "name": "extract_test",
            "word": "identifier",
            "rules": {
                "source": {
                    "type": "CHOICE",
                    "members": [
                        {"type": "STRING", "value": "let"},
                        {"type": "STRING", "value": "var"},
                        {"type": "STRING", "value": "+"},
                        {"type": "SYMBOL", "name": "identifier"}
                    ]
                },
                "identifier": {"type": "PATTERN", "value": "[a-zA-Z_]\\\\w*"}
            }
        }
        """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let keywords = KeywordExtractor.extract(from: grammar)
        #expect(keywords["let"] != nil)
        #expect(keywords["var"] != nil)
        #expect(keywords["+"] == nil) // Not word-like
    }
}
