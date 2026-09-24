import Foundation
import Testing

@testable import AtelierSearch

@Suite("Search engine — findMatches")
struct SearchEngineTests {
    @Test(arguments: [false, true])
    func `matches stop at the requested cap`(regex: Bool) throws {
        let pattern = try #require(compilePattern(SearchQuery(text: "a", isRegex: regex)))
        let matches = findMatches(in: ["aaaa", "aaaa"], pattern: pattern, maxMatches: 5)
        #expect(
            matches == [
                SearchMatch(row: 0, colStart: 0, colEnd: 1),
                SearchMatch(row: 0, colStart: 1, colEnd: 2),
                SearchMatch(row: 0, colStart: 2, colEnd: 3),
                SearchMatch(row: 0, colStart: 3, colEnd: 4),
                SearchMatch(row: 1, colStart: 0, colEnd: 1)
            ])
        #expect(findMatches(in: ["a"], pattern: pattern, maxMatches: 0).isEmpty)
        #expect(!scanMatches(in: ["aaaa", "aaaa"], pattern: pattern, maxMatches: 5).isComplete)
    }

    @Test
    func `an expired regex budget marks a result incomplete below its match cap`() throws {
        let pattern = try #require(compilePattern(SearchQuery(text: "id[0-9]+", isRegex: true)))
        let result = scanMatches(
            in: ["id1", "id2"], pattern: pattern, maxMatches: 5_000, deadline: ContinuousClock.now)
        #expect(result.matches.isEmpty)
        #expect(!result.isComplete)
    }

    @Test
    func `a scan that reaches the end reports a complete result`() throws {
        let pattern = try #require(compilePattern(SearchQuery(text: "id")))
        let result = scanMatches(in: ["id1", "none", "id2"], pattern: pattern, maxMatches: 5_000)
        #expect(result.matches.count == 2)
        #expect(result.isComplete)
    }

    @Test
    func `a cancelled literal scan reports an incomplete result`() async throws {
        let pattern = try #require(compilePattern(SearchQuery(text: "id")))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return scanMatches(in: ["id1", "id2"], pattern: pattern, maxMatches: 5_000)
        }
        let result = await task.value
        #expect(result.matches.isEmpty)
        #expect(!result.isComplete)
    }

    // MARK: - Literal search

    @Test("Literal: single match")
    func literalSingleMatch() {
        let lines = ["hello world"]
        let pattern = compilePattern(SearchQuery(text: "world"))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches == [SearchMatch(row: 0, colStart: 6, colEnd: 11)])
    }

    @Test("Literal: multiple matches per line")
    func literalMultiplePerLine() {
        let lines = ["aaa"]
        let pattern = compilePattern(SearchQuery(text: "a"))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 3)
        #expect(matches[0] == SearchMatch(row: 0, colStart: 0, colEnd: 1))
        #expect(matches[1] == SearchMatch(row: 0, colStart: 1, colEnd: 2))
        #expect(matches[2] == SearchMatch(row: 0, colStart: 2, colEnd: 3))
    }

    @Test("Literal: matches across multiple lines")
    func literalMultipleLines() {
        let lines = ["foo bar", "baz", "foo baz"]
        let pattern = compilePattern(SearchQuery(text: "foo"))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 2)
        #expect(matches[0].row == 0)
        #expect(matches[1].row == 2)
    }

    @Test("Literal: case-insensitive")
    func literalCaseInsensitive() {
        let lines = ["Hello HELLO hello"]
        let pattern = compilePattern(SearchQuery(text: "hello", isCaseSensitive: false))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 3)
    }

    @Test("Literal: case-sensitive")
    func literalCaseSensitive() {
        let lines = ["Hello HELLO hello"]
        let pattern = compilePattern(SearchQuery(text: "hello", isCaseSensitive: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 1)
        #expect(matches[0].colStart == 12)
    }

    @Test("Literal: no matches returns empty")
    func literalNoMatches() {
        let lines = ["hello world"]
        let pattern = compilePattern(SearchQuery(text: "xyz"))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.isEmpty)
    }

    @Test("Literal: empty lines array returns empty")
    func literalEmptyLines() {
        let pattern = compilePattern(SearchQuery(text: "test"))!
        let matches = findMatches(in: [], pattern: pattern, maxMatches: 10_000)
        #expect(matches.isEmpty)
    }

    // MARK: - Regex search

    @Test("Regex: simple pattern")
    func regexSimple() {
        let lines = ["abc 123 def"]
        let pattern = compilePattern(SearchQuery(text: "\\d+", isRegex: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 1)
        #expect(matches[0] == SearchMatch(row: 0, colStart: 4, colEnd: 7))
    }

    @Test("Regex: case-insensitive")
    func regexCaseInsensitive() {
        let lines = ["Hello WORLD"]
        let pattern = compilePattern(
            SearchQuery(text: "hello", isCaseSensitive: false, isRegex: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 1)
    }

    @Test("Regex: multi-match per line")
    func regexMultiMatch() {
        let lines = ["cat 12 dog 34"]
        let pattern = compilePattern(SearchQuery(text: "\\d+", isRegex: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 2)
        #expect(matches[0] == SearchMatch(row: 0, colStart: 4, colEnd: 6))
        #expect(matches[1] == SearchMatch(row: 0, colStart: 11, colEnd: 13))
    }

    @Test("Regex: anchors")
    func regexAnchors() {
        let lines = ["hello world", "world hello"]
        let pattern = compilePattern(SearchQuery(text: "^hello", isRegex: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 1)
        #expect(matches[0].row == 0)
    }

    @Test("Regex: special characters in pattern")
    func regexSpecialChars() {
        let lines = ["price is $100"]
        let pattern = compilePattern(SearchQuery(text: "\\$\\d+", isRegex: true))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 1)
        #expect(matches[0] == SearchMatch(row: 0, colStart: 9, colEnd: 13))
    }

    // MARK: - Non-overlapping literal matches

    @Test("Literal: non-overlapping matches")
    func literalNonOverlapping() {
        let lines = ["aaaa"]
        let pattern = compilePattern(SearchQuery(text: "aa"))!
        let matches = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        #expect(matches.count == 2)
        #expect(matches[0] == SearchMatch(row: 0, colStart: 0, colEnd: 2))
        #expect(matches[1] == SearchMatch(row: 0, colStart: 2, colEnd: 4))
    }

    /// Machine-dependent wall-clock timing may not gate the default run (`AGENTS.md`), so this
    /// only runs and prints its measurement under `ATELIER_BENCH=1 swift test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `regex progress callbacks interrupt catastrophic backtracking`() throws {
        let lines = [String(repeating: "a", count: 30)]
        let pattern = try #require(compilePattern(SearchQuery(text: "(a+)+b", isRegex: true)))
        let start = ContinuousClock.now
        _ = findMatches(in: lines, pattern: pattern, maxMatches: 10_000)
        let elapsed = start.duration(to: .now)
        print("catastrophic-backtracking pattern completed in \(elapsed) (budget 2 s)")
    }
}
