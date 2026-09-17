import Testing

@testable import AtelierSearch

@Test(arguments: ["", "abc"])
func `zero width anchors keep their original line boundaries`(line: String) throws {
    let start = try #require(compilePattern(SearchQuery(text: "^", isRegex: true)))
    let end = try #require(compilePattern(SearchQuery(text: "$", isRegex: true)))
    #expect(
        findMatches(in: [line], pattern: start) == [SearchMatch(row: 0, colStart: 0, colEnd: 0)])
    #expect(
        findMatches(in: [line], pattern: end) == [
            SearchMatch(row: 0, colStart: line.count, colEnd: line.count)
        ])
}

@Test
func `regex positions use character columns after emoji`() throws {
    let pattern = try #require(compilePattern(SearchQuery(text: "cat", isRegex: true)))
    #expect(
        findMatches(in: ["👩‍💻 cat"], pattern: pattern) == [
            SearchMatch(row: 0, colStart: 2, colEnd: 5)
        ])
}

@Test
func `regex never splits a character during replacement`() throws {
    let pattern = try #require(compilePattern(SearchQuery(text: "e", isRegex: true)))
    #expect(findMatches(in: ["e\u{301}"], pattern: pattern).isEmpty)
    let grapheme = try #require(compilePattern(SearchQuery(text: "\\X", isRegex: true)))
    let matches = findMatches(in: ["👩‍💻"], pattern: grapheme)
    #expect(matches == [SearchMatch(row: 0, colStart: 0, colEnd: 1)])
    #expect(
        applyReplacements(to: ["👩‍💻"], matches: matches, pattern: grapheme, replacement: "x").newLines
            == ["x"])
}

@Test
func `replacement preserves alternation and empty optional captures`() throws {
    let pattern = try #require(compilePattern(SearchQuery(text: "(a|ab)(c)?", isRegex: true)))
    let match = SearchMatch(row: 0, colStart: 0, colEnd: 2)
    #expect(buildReplacement(for: match, in: "ab", pattern: pattern, replacement: "$1:$2") == "ab:")
}
