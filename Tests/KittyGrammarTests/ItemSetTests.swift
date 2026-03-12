import Foundation
import Testing

@testable import KittyGrammar

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
