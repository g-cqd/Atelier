import Foundation
import Testing

@testable import KittyGrammar

@Suite
struct GrammarDefinitionTests {
    @Test
    func `Rule enum variants`() {
        let sym = Rule.symbol("identifier")
        let str = Rule.string("if")
        let blank = Rule.blank
        #expect(sym == .symbol("identifier"))
        #expect(str == .string("if"))
        #expect(blank == .blank)
    }

    @Test
    func `Equality compares all stored properties`() {
        let lhs = GrammarDefinition(
            name: "shared",
            rules: [("source", .symbol("statement"))],
            extras: [.pattern("\\s+")],
            conflicts: [["source", "statement"]],
            externals: [.symbol("external_token")],
            inline: ["statement"],
            word: "identifier",
            supertypes: ["expression"],
            precedences: [[.symbol("statement")]]
        )
        let rhs = GrammarDefinition(
            name: "shared",
            rules: [("source", .string("statement"))],
            extras: [.pattern("\\s+")],
            conflicts: [["source", "statement"]],
            externals: [.symbol("external_token")],
            inline: ["statement"],
            word: "identifier",
            supertypes: ["expression"],
            precedences: [[.symbol("statement")]]
        )

        #expect(lhs != rhs)
    }
}

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

private enum GrammarRuleExpectationError: Error {
    case expectedStringRule
}

private func requireStringRule(_ rule: Rule?) throws -> String {
    guard case .some(.string(let value)) = rule else {
        throw GrammarRuleExpectationError.expectedStringRule
    }
    return value
}

@Suite
struct ItemSetTests {
    @Test
    func `Basic closure`() throws {
        // S -> . E, E -> . "a"
        let productions: [(name: String, symbols: [String])] = [
            ("S'", ["S"]),
            ("S", ["E"]),
            ("E", ["\"a\""]),
        ]
        let firstSets: [String: Set<String>] = [
            "S'": ["\"a\""],
            "S": ["\"a\""],
            "E": ["\"a\""],
            "\"a\"": ["\"a\""],
            "$end": ["$end"],
        ]
        let rulesByNT: [String: [Int]] = ["S'": [0], "S": [1], "E": [2]]

        let initial = ItemSet(items: [LRItem(ruleIndex: 0, dotPosition: 0, lookahead: "$end")])
        let closed = try initial.closure(
            productions: productions,
            firstSets: firstSets,
            rulesByNonTerminal: rulesByNT,
            limits: .default
        )

        // Should contain items for S and E productions
        #expect(closed.items.count > 1)
    }
}

@Suite
struct ParseTableCompilerTests {
    @Test
    func `Compile simple grammar`() throws {
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

    @Test
    func `repeat compiles to recursive zero or more productions`() throws {
        let json = """
            {
                "name": "repeat_test",
                "rules": {
                    "source": {
                        "type": "REPEAT",
                        "content": {
                            "type": "SYMBOL",
                            "name": "item"
                        }
                    },
                    "item": {
                        "type": "STRING",
                        "value": "a"
                    }
                }
            }
            """

        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let sourceRule = try #require(result.productions.first { $0.name == "source" })
        let helperName = try #require(sourceRule.symbols.first)
        #expect(helperName.starts(with: "_repeat_"))

        let helperRules = result.productions.filter { $0.name == helperName }
        #expect(helperRules.contains { $0.symbols.isEmpty })
        #expect(helperRules.contains { $0.symbols == [helperName, "item"] })
    }

    @Test
    func `repeat1 compiles to recursive one or more productions`() throws {
        let json = """
            {
                "name": "repeat1_test",
                "rules": {
                    "source": {
                        "type": "REPEAT1",
                        "content": {
                            "type": "SYMBOL",
                            "name": "item"
                        }
                    },
                    "item": {
                        "type": "STRING",
                        "value": "a"
                    }
                }
            }
            """

        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let sourceRule = try #require(result.productions.first { $0.name == "source" })
        let helperName = try #require(sourceRule.symbols.first)
        #expect(helperName.starts(with: "_repeat1_"))

        let helperRules = result.productions.filter { $0.name == helperName }
        #expect(!helperRules.contains { $0.symbols.isEmpty })
        #expect(helperRules.contains { $0.symbols == ["item"] })
        #expect(helperRules.contains { $0.symbols == [helperName, "item"] })
    }

    @Test
    func `Fields are preserved on flattened productions`() throws {
        let json = """
            {
                "name": "fields_test",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [
                            {
                                "type": "FIELD",
                                "name": "left",
                                "content": {
                                    "type": "SYMBOL",
                                    "name": "lhs"
                                }
                            },
                            {
                                "type": "STRING",
                                "value": "="
                            },
                            {
                                "type": "FIELD",
                                "name": "right",
                                "content": {
                                    "type": "SYMBOL",
                                    "name": "rhs"
                                }
                            }
                        ]
                    },
                    "lhs": {
                        "type": "STRING",
                        "value": "a"
                    },
                    "rhs": {
                        "type": "STRING",
                        "value": "b"
                    }
                }
            }
            """

        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let result = try ParseTableCompiler.compile(grammar)

        let sourceRule = try #require(
            result.productions.first {
                $0.name == "source" && $0.symbols == ["lhs", "\"=\"", "rhs"]
            })

        #expect(sourceRule.fields == [0: "left", 2: "right"])
    }

    @Test
    func `Compile rejects rule expansion that exceeds configured limits`() throws {
        let json = """
            {
                "name": "explosive",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "a"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "b"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "c"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "d"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "e"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "f"}, {"type": "BLANK"}]},
                            {"type": "CHOICE", "members": [{"type": "STRING", "value": "g"}, {"type": "BLANK"}]}
                        ]
                    }
                }
            }
            """

        let grammar = try GrammarLoader.parse(Data(json.utf8))

        #expect(
            throws: GrammarError.resourceLimitExceeded(
                "Sequence expansion for source exceeded limit (128 alternatives, limit 64)"
            )
        ) {
            try ParseTableCompiler.compile(
                grammar,
                limits: GrammarCompilationLimits(
                    maxExpandedAlternativesPerRule: 64,
                    maxFlattenedProductions: 1_000,
                    maxProductionSymbols: 1_000,
                    maxItemsPerState: 1_000,
                    maxStates: 100,
                    maxTransitions: 1_000
                )
            )
        }
    }

    @Test
    func `Compile rejects parser state growth that exceeds configured limits`() throws {
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

        #expect(
            throws: GrammarError.resourceLimitExceeded(
                "Parser state construction exceeded limit (2 states, limit 1)"
            )
        ) {
            try ParseTableCompiler.compile(
                grammar,
                limits: GrammarCompilationLimits(
                    maxExpandedAlternativesPerRule: 64,
                    maxFlattenedProductions: 1_000,
                    maxProductionSymbols: 1_000,
                    maxItemsPerState: 1_000,
                    maxStates: 1,
                    maxTransitions: 1_000
                )
            )
        }
    }
}

@Suite
struct LexTableCompilerTests {
    @Test
    func `Extract keywords from grammar`() throws {
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

@Suite
struct LexTableCompilerCommentPatternsTests {
    @Test
    func `Extracts line comment pattern from grammar extras`() throws {
        let json = """
            {
                "name": "comment_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "\\\\/\\\\/[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
    }

    @Test
    func `Extracts block comment pattern from grammar extras`() throws {
        let json = """
            {
                "name": "block_comment_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "CHOICE",
                            "members": [
                                {"type": "PATTERN", "value": "\\\\/\\\\/[^\\\\n]*"},
                                {"type": "PATTERN", "value": "\\\\/\\\\*[^*]*\\\\*+([^\\\\/*][^*]*\\\\*+)*\\\\/"}
                            ]
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
        #expect(lexTable.commentPatterns.contains(.block(open: "/*", close: "*/")))
    }

    @Test
    func `Returns empty comment patterns when no extras define comments`() throws {
        let json = """
            {
                "name": "no_comments",
                "rules": {
                    "source": {"type": "STRING", "value": "x"}
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.isEmpty)
    }

    @Test
    func `Swift grammar extras produce both line and block comment patterns`() throws {
        let json = """
            {
                "name": "swift_like",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "CHOICE",
                            "members": [
                                {
                                    "type": "SEQ",
                                    "members": [{"type": "PATTERN", "value": "\\\\/{2,3}[^\\\\/].*"}]
                                },
                                {
                                    "type": "SEQ",
                                    "members": [{"type": "PATTERN", "value": "\\\\/\\\\*{1,}[^*]*\\\\*+([^\\\\/*][^*]*\\\\*+)*\\\\/"}]
                                }
                            ]
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
        #expect(lexTable.commentPatterns.contains(.block(open: "/*", close: "*/")))
    }

    @Test
    func `Hash line comment pattern is extracted`() throws {
        let json = """
            {
                "name": "hash_comment",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "#[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "#")))
    }
}

@Suite
struct CommentPatternCodableTests {
    @Test
    func `Line comment pattern round-trips through Codable`() throws {
        let pattern = CommentPattern.line(prefix: "//")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CommentPattern.self, from: data)
        #expect(decoded == pattern)
    }

    @Test
    func `Block comment pattern round-trips through Codable`() throws {
        let pattern = CommentPattern.block(open: "/*", close: "*/")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CommentPattern.self, from: data)
        #expect(decoded == pattern)
    }
}

@Suite
struct KeywordExtractorTests {
    @Test
    func `Extracts word-like keywords`() throws {
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
        #expect(keywords["+"] == nil)  // Not word-like
    }
}
