import Foundation
import Testing

@testable import KittySearch

@Suite("SearchReplace")
struct SearchReplaceTests {
    @Test("literal replacement works")
    func literalReplacement() {
        let pattern = SearchPattern.literal(text: "hello", caseSensitive: true)
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 5)
        let result = buildReplacement(for: match, in: "hello world", pattern: pattern, replacement: "hi")
        #expect(result == "hi")
    }

    @Test("regex capture group substitution")
    func regexCaptureGroups() {
        let regex = try! Regex("(\\w+)_(\\w+)")
        let pattern = SearchPattern.regex(regex)
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 11)
        let result = buildReplacement(
            for: match, in: "hello_world", pattern: pattern, replacement: "$2_$1")
        #expect(result == "world_hello")
    }

    @Test("reverse-order application preserves positions")
    func reverseOrderPreservesPositions() {
        let lines = ["hello hello"]
        let pattern = SearchPattern.literal(text: "hello", caseSensitive: true)
        let matches = [
            SearchMatch(row: 0, colStart: 0, colEnd: 5),
            SearchMatch(row: 0, colStart: 6, colEnd: 11),
        ]

        let (newLines, count) = applyReplacements(
            to: lines, matches: matches, pattern: pattern, replacement: "hi")

        #expect(count == 2)
        #expect(newLines[0] == "hi hi")
    }

    @Test("empty replacement deletes matches")
    func emptyReplacementDeletes() {
        let lines = ["hello world"]
        let pattern = SearchPattern.literal(text: "hello ", caseSensitive: true)
        let matches = [SearchMatch(row: 0, colStart: 0, colEnd: 6)]

        let (newLines, count) = applyReplacements(
            to: lines, matches: matches, pattern: pattern, replacement: "")

        #expect(count == 1)
        #expect(newLines[0] == "world")
    }

    @Test("replacement across multiple lines")
    func multiLineReplacement() {
        let lines = ["hello world", "hello there", "goodbye"]
        let pattern = SearchPattern.literal(text: "hello", caseSensitive: true)
        let matches = [
            SearchMatch(row: 0, colStart: 0, colEnd: 5),
            SearchMatch(row: 1, colStart: 0, colEnd: 5),
        ]

        let (newLines, count) = applyReplacements(
            to: lines, matches: matches, pattern: pattern, replacement: "hi")

        #expect(count == 2)
        #expect(newLines[0] == "hi world")
        #expect(newLines[1] == "hi there")
        #expect(newLines[2] == "goodbye")
    }

    @Test("case-insensitive literal replacement")
    func caseInsensitiveLiteral() {
        let pattern = SearchPattern.literal(text: "HELLO", caseSensitive: false)
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 5)
        let result = buildReplacement(for: match, in: "hello world", pattern: pattern, replacement: "HI")
        #expect(result == "HI")
    }

    @Test("$0 captures full regex match")
    func dollarZeroCapturesFullMatch() {
        let regex = try! Regex("\\d+")
        let pattern = SearchPattern.regex(regex)
        let match = SearchMatch(row: 0, colStart: 5, colEnd: 8)
        let result = buildReplacement(
            for: match, in: "line 123 end", pattern: pattern, replacement: "[$0]")
        #expect(result == "[123]")
    }
}
