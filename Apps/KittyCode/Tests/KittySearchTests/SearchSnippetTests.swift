import Testing

@testable import KittySearch

@Suite("Snippet extraction")
struct SearchSnippetTests {
    let sampleLines = [
        "line 0: first",
        "line 1: second",
        "line 2: third",
        "line 3: fourth",
        "line 4: fifth"
    ]

    @Test("Returns matched line with no context")
    func matchedLineOnly() {
        let match = SearchMatch(row: 2, colStart: 0, colEnd: 5)
        let snippet = extractSnippet(from: sampleLines, match: match)
        #expect(snippet == "line 2: third")
    }

    @Test("Returns context lines around match")
    func withContext() {
        let match = SearchMatch(row: 2, colStart: 0, colEnd: 5)
        let snippet = extractSnippet(from: sampleLines, match: match, contextLines: 1)
        #expect(snippet == "line 1: second\nline 2: third\nline 3: fourth")
    }

    @Test("Clamps at start of file")
    func clampStart() {
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 4)
        let snippet = extractSnippet(from: sampleLines, match: match, contextLines: 2)
        #expect(snippet == "line 0: first\nline 1: second\nline 2: third")
    }

    @Test("Clamps at end of file")
    func clampEnd() {
        let match = SearchMatch(row: 4, colStart: 0, colEnd: 4)
        let snippet = extractSnippet(from: sampleLines, match: match, contextLines: 2)
        #expect(snippet == "line 2: third\nline 3: fourth\nline 4: fifth")
    }

    @Test("Empty lines returns empty string")
    func emptyLines() {
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 1)
        let snippet = extractSnippet(from: [], match: match)
        #expect(snippet == "")
    }

    @Test("Out of bounds row returns empty string")
    func outOfBounds() {
        let match = SearchMatch(row: 10, colStart: 0, colEnd: 1)
        let snippet = extractSnippet(from: sampleLines, match: match)
        #expect(snippet == "")
    }
}
