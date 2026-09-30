import Foundation
import Testing

@testable import AtelierGrammar

/// The compact tables read back exactly the rows, targets and moves they were built from.
@Suite
struct CompactTableTests {
    private static let reduction = Action.reduce(ruleIndex: 2, count: 3, nonTerminal: "expression")
    private static let conflict = Action.conflict([.reduce(ruleIndex: 1, count: 1, nonTerminal: "term"), .shift(4)])

    @Test
    func `an action table reads back every action of its rows, shared rows stored once`() {
        let rows: [[Action]] = [
            [.shift(1), .error, Self.reduction],
            [.accept, Self.conflict, .error],
            [.shift(1), .error, Self.reduction],
            [.shift(Int(ParseActionTable.payloadMask) + 1), .shift(-1), Self.reduction]
        ]
        let table = ParseActionTable(rows: rows)

        #expect(table.rows == rows)
        #expect(table.stateCount == 4)
        #expect(table.rowCount == 3)
        #expect(table.indirectActions == [Self.reduction, Self.conflict, .shift(1 << 30), .shift(-1)])
        #expect(table.isError(state: 0, terminal: 1))
        #expect(!table.isError(state: 1, terminal: 0))
        #expect(table.isWellFormed)
    }

    @Test
    func `setting an action changes only its state, though its row is shared`() {
        var table = ParseActionTable(rows: [[.shift(1), .error], [.shift(1), .error]])

        table[1, 1] = Self.reduction

        #expect(table.rows == [[.shift(1), .error], [.shift(1), Self.reduction]])
        #expect(table.isWellFormed)
    }

    @Test
    func `a short row of actions reads as errors past its end`() {
        let table = ParseActionTable(rows: [[.shift(1)], [.accept, .shift(0)]])

        #expect(table.columnCount == 2)
        #expect(table[0, 1] == .error)
    }

    @Test
    func `a goto table reads back every target, those no cell holds included`() {
        let rows: [[Int?]] = [[nil, 3], [0, nil], [nil, 3], [Int(Int32.max), -2]]
        var table = ParseGotoTable(rows: rows)

        #expect(table.rows == rows)
        #expect(table.rowCount == 3)
        #expect(table.isWellFormed)

        table[2, 0] = 7

        #expect(table.rows == [[nil, 3], [0, nil], [7, 3], [Int(Int32.max), -2]])
    }

    @Test
    func `external validity keeps each distinct row once`() {
        let validity = ExternalValidity(rows: [[true, false], [false, false], [true, false]])

        #expect(Array(validity) == [[true, false], [false, false], [true, false]])
        #expect(validity.distinctRows.count == 2)
        #expect(validity == ExternalValidity(rows: Array(validity)))
    }

    @Test
    func `compact tables encode as the rows the tables' JSON always held`() throws {
        let actions = ParseActionTable(rows: [[.shift(1), Self.reduction], [.error, Self.conflict]])
        let gotos = ParseGotoTable(rows: [[nil, 2], [1, nil]])

        let actionJSON = try JSONEncoder().encode(actions)
        let gotoJSON = try JSONEncoder().encode(gotos)

        #expect(try JSONDecoder().decode([[Action]].self, from: actionJSON) == actions.rows)
        #expect(try JSONDecoder().decode(ParseActionTable.self, from: actionJSON) == actions)
        #expect(try JSONDecoder().decode([[Int?]].self, from: gotoJSON) == gotos.rows)
        #expect(try JSONDecoder().decode(ParseGotoTable.self, from: gotoJSON) == gotos)
    }

    @Test
    func `a lexer automaton reads back its states, and moves as a search of their sorted moves does`() throws {
        let compiled = try Self.compiledWithUnicodeWords()
        let automaton = compiled.lexTable.automaton
        let states = Array(automaton)

        #expect(LexAutomaton(states) == automaton)
        #expect(automaton.isWellFormed)
        let scalars: [UInt32] = [0, 0x20, 0x41, 0x5F, 0x61, 0x7F, 0x80, 0xE9, 0x3A9, 0x4E00, 0x1F600, 0x10FFFF]
        for (state, moves) in states.enumerated() {
            for scalar in scalars {
                let expected = moves.transitions.first { $0.lower <= scalar && scalar <= $0.upper }
                let move = automaton.move(from: state, on: scalar)
                #expect(move?.target == expected?.target && move?.skips == expected?.skips)
            }
        }
    }

    /// Words of Unicode letters between spaces, so many lexer states read the same large set of ranges.
    private static func compiledWithUnicodeWords() throws -> ParseTableCompiler.CompilationResult {
        let json = #"""
            {
                "name": "words",
                "rules": {
                    "source": {"type": "REPEAT", "content": {"type": "CHOICE", "members": [
                        {"type": "SYMBOL", "name": "word"}, {"type": "SYMBOL", "name": "number"},
                        {"type": "STRING", "value": "ab"}
                    ]}},
                    "word": {"type": "PATTERN", "value": "[\\p{L}_][\\p{L}\\d_]*"},
                    "number": {"type": "PATTERN", "value": "\\d+"}
                },
                "extras": [{"type": "PATTERN", "value": "\\s"}]
            }
            """#
        return try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
    }
}
