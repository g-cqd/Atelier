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

    @Test("Case-insensitive regex matches different case")
    func caseInsensitiveRegex() {
        let query = SearchQuery(text: "hello", isCaseSensitive: false, isRegex: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern")
            return
        }
        // Verify case-insensitive matching works
        let line = "HELLO world"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 1)
    }

    @Test("Case-sensitive regex does not match different case")
    func caseSensitiveRegex() {
        let query = SearchQuery(text: "hello", isCaseSensitive: true, isRegex: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern")
            return
        }
        let line = "HELLO world"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 0)
    }

    // MARK: - Whole-word literal

    @Test("Whole-word literal matches standalone word")
    func wholeWordLiteralMatchesStandaloneWord() {
        let query = SearchQuery(text: "foo", wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word literal")
            return
        }
        let line = "foo bar baz"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 1)
    }

    @Test("Whole-word literal does not match substring")
    func wholeWordLiteralDoesNotMatchSubstring() {
        let query = SearchQuery(text: "foo", wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word literal")
            return
        }
        let line = "foobar foobaz"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 0)
    }

    @Test("Whole-word literal matches multiple standalone occurrences")
    func wholeWordLiteralMatchesMultipleOccurrences() {
        let query = SearchQuery(text: "foo", wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word literal")
            return
        }
        let line = "foo and foo again"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 2)
    }

    @Test("Whole-word literal case-insensitive matches standalone word")
    func wholeWordLiteralCaseInsensitive() {
        let query = SearchQuery(text: "foo", isCaseSensitive: false, wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word case-insensitive literal")
            return
        }
        let line = "FOO bar"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 1)
    }

    @Test("Whole-word literal case-sensitive does not match different case")
    func wholeWordLiteralCaseSensitiveNoMatch() {
        let query = SearchQuery(text: "foo", isCaseSensitive: true, wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word case-sensitive literal")
            return
        }
        let line = "FOO bar"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 0)
    }

    // MARK: - Whole-word regex

    @Test("Whole-word regex matches standalone word")
    func wholeWordRegexMatchesStandaloneWord() {
        let query = SearchQuery(text: "fo+", isRegex: true, wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word regex")
            return
        }
        let line = "foo bar"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 1)
    }

    @Test("Whole-word regex does not match substring")
    func wholeWordRegexDoesNotMatchSubstring() {
        let query = SearchQuery(text: "fo+", isRegex: true, wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word regex")
            return
        }
        let line = "foobar"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 0)
    }

    @Test("Whole-word regex case-insensitive matches standalone word")
    func wholeWordRegexCaseInsensitive() {
        let query = SearchQuery(text: "fo+", isCaseSensitive: false, isRegex: true, wholeWord: true)
        guard let pattern = compilePattern(query), case .regex = pattern else {
            Issue.record("Expected regex pattern for whole-word case-insensitive regex")
            return
        }
        let line = "FOO bar"
        let matches = findMatches(in: [line], pattern: pattern)
        #expect(matches.count == 1)
    }
}
