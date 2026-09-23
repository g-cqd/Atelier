import Testing

@testable import AtelierSearch

/// Replacement templates are expanded from the match the search found in the whole line, so what an expression
/// looks at around its match takes part in the replacement as it did in the search.
struct RegexReplaceExpansionTests {
    private static func replacingAll(_ pattern: String, with template: String, in line: String) throws -> String {
        let compiled = try #require(compilePattern(SearchQuery(text: pattern, isCaseSensitive: true, isRegex: true)))
        let matches = findMatches(in: [line], pattern: compiled)
        return applyReplacements(to: [line], matches: matches, pattern: compiled, replacement: template).newLines[0]
    }

    @Test
    func `a capture behind a lookbehind expands from the whole line`() throws {
        #expect(try Self.replacingAll(#"(?<=let )(\w+)"#, with: "$1_", in: "let x = 1") == "let x_ = 1")
    }

    @Test(arguments: [
        (#"(\w+)(?=\()"#, "$1_", "call(x)", "call_(x)"),
        (#"\b(-)\b"#, "[$1]", "a-b", "a[-]b"),
        (#"\B(x)"#, "<$1>", "ax x", "a<x> x"),
        (#"(y)\B"#, "<$1>", "ya y", "<y>a y")
    ])
    func `a lookahead or a word boundary at a match edge still expands`(
        pattern: String, template: String, line: String, expected: String
    ) throws {
        #expect(try Self.replacingAll(pattern, with: template, in: line) == expected)
    }

    @Test
    func `a lookahead reaching the neighbouring replacement sees the original line`() throws {
        // Each letter is followed by `-` and a letter only in the original line: once `b` becomes `[b]`, the
        // lookahead after `a` would fail.
        #expect(try Self.replacingAll(#"(\w)(?=-\w)"#, with: "[$1]", in: "a-b-c") == "[a]-[b]-c")
    }

    @Test(arguments: [
        #"(?<=let )(\w+)"#, #"(?<!\d)(\d)"#, #"(\w+)(?=;)"#, #"(\w)(?!\w)"#, #"\b(\w)"#, #"(\w)\b"#, #"^(\w+)"#,
        #"(\w+)$"#, #"(a|ab)(c)?"#, #"(?<=\()(\w+)(?=\))"#
    ])
    func `no replacement ever writes an unexpanded capture reference`(pattern: String) throws {
        let lines = ["let x = 1;", "call(arg); a1 b22", "ab abc abx", "(x) (yy);", "", "é e\u{301}"]
        let compiled = try #require(compilePattern(SearchQuery(text: pattern, isCaseSensitive: true, isRegex: true)))
        let matches = findMatches(in: lines, pattern: compiled)
        #expect(!matches.isEmpty)
        let replaced = applyReplacements(to: lines, matches: matches, pattern: compiled, replacement: "$1")
        #expect(replaced.newLines.allSatisfy { !$0.contains("$1") })
        #expect(replaced.replacementCount == matches.count)
    }

    @Test
    func `a match the expression no longer finds is left as it is and not counted`() throws {
        let pattern = try #require(compilePattern(SearchQuery(text: #"(\d+)"#, isCaseSensitive: true, isRegex: true)))
        let stale = SearchMatch(row: 0, colStart: 0, colEnd: 3)
        let expanded: String? = buildReplacement(for: stale, in: "abc 12", pattern: pattern, replacement: "<$1>")
        #expect(expanded == nil)
        let replaced = applyReplacements(to: ["abc 12"], matches: [stale], pattern: pattern, replacement: "<$1>")
        #expect(replaced.newLines == ["abc 12"])
        #expect(replaced.replacementCount == 0)
    }

    @Test
    func `a match whose end moved is left as it is`() throws {
        // The line was edited after the search: the expression still starts at column 4 but ends elsewhere.
        let pattern = try #require(compilePattern(SearchQuery(text: #"\d+"#, isCaseSensitive: true, isRegex: true)))
        let stale = SearchMatch(row: 0, colStart: 4, colEnd: 6)
        let expanded: String? = buildReplacement(for: stale, in: "abc 1234", pattern: pattern, replacement: "n")
        #expect(expanded == nil)
    }
}
