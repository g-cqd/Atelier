import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct GLRParserTerminationTests {
    @Test(arguments: ["[[]]", "[{},{}]", "[true,false,null]"])
    func `JSON that used to reduce forever parses without an error`(source: String) throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)

        let tree = try parser.parse(source)

        #expect(tree.root.type == "document")
        #expect(!tree.root.containsError)
    }

    @Test
    func `Forks of a reduce-reduce conflict keep reducing and parse without an error`() throws {
        // The review's grammar: `x` reduces from `a` or `b`, each of which is the same token, and both forks must
        // reduce once more before `z` can shift.
        let json = """
            {
                "name": "conflict",
                "rules": {
                    "s": {
                        "type": "SEQ",
                        "members": [{"type": "SYMBOL", "name": "x"}, {"type": "STRING", "value": "z"}]
                    },
                    "x": {
                        "type": "CHOICE",
                        "members": [{"type": "SYMBOL", "name": "a"}, {"type": "SYMBOL", "name": "b"}]
                    },
                    "a": {"type": "STRING", "value": "id"},
                    "b": {"type": "STRING", "value": "id"}
                }
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("id z")

        #expect(tree.root.type == "s")
        #expect(tree.root.children.map(\.type) == ["x", "\"z\""])
        #expect(!tree.root.containsError)
    }

    @Test
    func `A reduction without a GOTO state is an error, not a loop`() throws {
        // `A → ε` reduces in state 1, which has no GOTO on `A`: staying in state 1 would reduce it again forever.
        let table = ParseTable(
            stateCount: 2,
            symbols: ["a", "$end", "A"],
            terminals: ["a", "$end"],
            nonTerminals: ["A"],
            actions: [
                [.shift(1), .error],
                [.error, .reduce(ruleIndex: 1, count: 0, nonTerminal: "A")]
            ],
            gotos: [[nil], [nil]]
        )
        let parser = GLRParser(
            parseTable: table,
            lexTable: LexTable(),
            productions: [
                ProductionRule(name: "_start", symbolCount: 1, symbols: ["A"]),
                ProductionRule(name: "A", symbolCount: 0, symbols: [])
            ]
        )

        let tree = try parser.parse("a")

        #expect(tree.root.type == "a")
    }

    @Test
    func `A table that reduces in a cycle stops at the reduction budget`() throws {
        // `A → A` reduces in state 1 and its GOTO leads back to state 1: without a budget it never stops.
        let table = ParseTable(
            stateCount: 2,
            symbols: ["a", "$end", "A"],
            terminals: ["a", "$end"],
            nonTerminals: ["A"],
            actions: [
                [.shift(1), .error],
                [.error, .reduce(ruleIndex: 1, count: 1, nonTerminal: "A")]
            ],
            gotos: [[1], [nil]]
        )
        let parser = GLRParser(
            parseTable: table,
            lexTable: LexTable(),
            productions: [
                ProductionRule(name: "_start", symbolCount: 1, symbols: ["A"]),
                ProductionRule(name: "A", symbolCount: 1, symbols: ["A"])
            ]
        )

        let tree = try parser.parse("a")

        #expect(tree.root.type == "A")
    }
}
