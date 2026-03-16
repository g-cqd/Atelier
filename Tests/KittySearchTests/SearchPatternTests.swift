import Testing

@testable import KittySearch

@Suite("SearchPattern compilation")
struct SearchPatternTests {
    @Test("Literal compilation always succeeds")
    func literalCompilation() {
        let query = SearchQuery(text: "hello")
        let pattern = compilePattern(query)
        guard case .literal(let text, let caseSensitive) = pattern else {
            Issue.record("Expected literal pattern")
            return
        }
        #expect(text == "hello")
        #expect(caseSensitive == false)
    }

    @Test("Case-sensitive literal compilation")
    func caseSensitiveLiteral() {
        let query = SearchQuery(text: "Hello", isCaseSensitive: true)
        let pattern = compilePattern(query)
        guard case .literal(_, let caseSensitive) = pattern else {
            Issue.record("Expected literal pattern")
            return
        }
        #expect(caseSensitive == true)
    }

    @Test("Regex compilation succeeds for valid patterns")
    func validRegex() {
        let query = SearchQuery(text: "\\d+", isRegex: true)
        let pattern = compilePattern(query)
        guard case .regex = pattern else {
            Issue.record("Expected regex pattern")
            return
        }
    }

    @Test("Regex compilation returns nil for invalid patterns")
    func invalidRegex() {
        let query = SearchQuery(text: "[invalid", isRegex: true)
        let pattern = compilePattern(query)
        #expect(pattern == nil)
    }

    @Test("Empty query returns nil")
    func emptyQuery() {
        let query = SearchQuery(text: "")
        #expect(compilePattern(query) == nil)
    }

    @Test("Empty regex query returns nil")
    func emptyRegexQuery() {
        let query = SearchQuery(text: "", isRegex: true)
        #expect(compilePattern(query) == nil)
    }

    @Test("Case-insensitive regex adds (?i) flag")
    func caseInsensitiveRegex() {
        let query = SearchQuery(text: "hello", isCaseSensitive: false, isRegex: true)
        guard let pattern = compilePattern(query), case .regex(let regex) = pattern else {
            Issue.record("Expected regex pattern")
            return
        }
        // Verify case-insensitive matching works
        let line = "HELLO world"
        let matches = line.matches(of: regex)
        #expect(matches.count == 1)
    }

    @Test("Case-sensitive regex does not match different case")
    func caseSensitiveRegex() {
        let query = SearchQuery(text: "hello", isCaseSensitive: true, isRegex: true)
        guard let pattern = compilePattern(query), case .regex(let regex) = pattern else {
            Issue.record("Expected regex pattern")
            return
        }
        let line = "HELLO world"
        let matches = line.matches(of: regex)
        #expect(matches.count == 0)
    }
}
