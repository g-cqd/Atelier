import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

func makeConflictParseTable() -> ParseTable {
    let terminals = ["a", "b", "$end"]
    let nonTerminals = ["Bad", "BadSingle", "Good"]
    let errorRow: [Action] = [.error, .error, .error]

    return ParseTable(
        stateCount: 6,
        symbols: terminals + nonTerminals,
        terminals: terminals,
        nonTerminals: nonTerminals,
        actions: [
            [
                .conflict([.shift(1), .shift(2)]),
                .error,
                .error
            ],
            [
                .error,
                .error,
                .conflict([
                    .reduce(ruleIndex: 1, count: 2, nonTerminal: "Bad"),
                    .reduce(ruleIndex: 2, count: 1, nonTerminal: "BadSingle")
                ])
            ],
            [
                .error,
                .shift(3),
                .error
            ],
            [
                .error,
                .error,
                .reduce(ruleIndex: 3, count: 2, nonTerminal: "Good")
            ],
            errorRow,
            [
                .error,
                .error,
                .accept
            ]
        ],
        gotos: [
            [4, 4, 5],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil],
            [nil, nil, nil]
        ]
    )
}
