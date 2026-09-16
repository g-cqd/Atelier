import Foundation
import Testing

@testable import AtelierGrammar

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
