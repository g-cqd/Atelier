import AtelierDiagnostics
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

@MainActor
struct DiagnosticRowMapperTests {
    private func finding(
        line: Int, column: Int? = nil, endLine: Int? = nil, endColumn: Int? = nil,
        severity: Finding.Severity = .warning, file: String = "a.swift", ruleID: String = "rule"
    ) -> Finding {
        Finding(
            tool: .swiftlint, ruleID: ruleID, message: "message", file: file, line: line, column: column,
            endLine: endLine, endColumn: endColumn, severity: severity)
    }

    @Test
    func `a finding on a visible row annotates that row with its severity and itself`() throws {
        let text = "line1\nline2\nline3\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 2)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let row = try #require(rows[1])
        #expect(row.severity == .warning)
        #expect(row.count == 1)
        #expect(row.findings == [finding(line: 2)])
    }

    @Test
    func `a finding on a line collapsed into a gap is absent`() throws {
        let old = "line1\nline2AAAA\nline3\n"
        let new = "line1\nline2BBBB\nline3\n"
        let diff = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 0, expansions: [:]))
        let rendered = try #require(diff.new)
        // The leading gap that hid "line1" takes no row: row 0 is line 2.
        #expect(rendered.rows[0].newNumber == 2)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        #expect(rows.isEmpty)
    }

    @Test
    func `a finding's column becomes a squiggle start clamped to the row's length`() throws {
        let text = "let alphaBeta = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1, column: 5)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let squiggle = try #require(rows[0]?.squiggles.first)
        #expect(squiggle.start == 4)
        #expect(squiggle.end == nil)
    }

    @Test
    func `a column past the end of the row clamps to the row's length`() throws {
        let text = "let x = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1, column: 999)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let squiggle = try #require(rows[0]?.squiggles.first)
        #expect(squiggle.start == "let x = 1".count)
    }

    @Test
    func `an end column on the same line sets the squiggle's end`() throws {
        let text = "let alphaBeta = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1, column: 5, endLine: 1, endColumn: 14)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let squiggle = try #require(rows[0]?.squiggles.first)
        #expect(squiggle.start == 4)
        #expect(squiggle.end == 13)
    }

    @Test
    func `an end line different from the start line leaves the squiggle's end open`() throws {
        let text = "let alphaBeta = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1, column: 5, endLine: 2, endColumn: 3)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let squiggle = try #require(rows[0]?.squiggles.first)
        #expect(squiggle.end == nil)
    }

    @Test
    func `a finding with no column leaves the row's squiggles empty, for a whole-line underline`() throws {
        let text = "let x = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 1)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let row = try #require(rows[0])
        #expect(row.squiggles.isEmpty)
    }

    @Test
    func `findings under a path that does not match the row's file are absent`() throws {
        let text = "let x = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["b.swift": [finding(line: 1, file: "b.swift")]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        #expect(rows.isEmpty)
    }

    @Test
    func `two findings on the same row combine into one count and the worse severity`() throws {
        let text = "let x = 1\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = [
            "a.swift": [
                finding(line: 1, severity: .note, ruleID: "note-rule"),
                finding(line: 1, severity: .error, ruleID: "error-rule")
            ]
        ]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        let row = try #require(rows[0])
        #expect(row.count == 2)
        #expect(row.severity == .error)
    }

    @Test
    func `a removed line is not annotated by default, even when its old line number matches a finding`() throws {
        // Removing the last line keeps every surviving row's new-side number distinct from the removed row's
        // old-side number, so a match can only come from the old-side fallback under test, never a coincidence.
        let old = "line1\nline2\nline3\n"
        let new = "line1\nline2\n"
        let rendered = try #require(DiffRenderer.render(oldText: old, newText: new, language: .plain).old)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 3)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        #expect(rows.isEmpty)
    }

    @Test
    func `a removed row never shows the right side's findings`() throws {
        let old = "line1\nline2\nline3\n"
        let new = "line1\nline2\n"
        let rendered = try #require(DiffRenderer.render(oldText: old, newText: new, language: .plain).old)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 3)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        #expect(rows.isEmpty)
    }

    @Test
    func `the old pane shows the left side's findings by old line number, and no right side's`() throws {
        let old = "line1\nline2\nline3\n"
        let new = "line1\nline2\n"
        let rendered = try #require(DiffRenderer.render(oldText: old, newText: new, language: .plain).old)
        let left = SideFindings(paths: [0: "a.swift"], findings: ["a.swift": [finding(line: 3, ruleID: "left")]])
        let right = SideFindings(paths: [0: "a.swift"], findings: ["a.swift": [finding(line: 1, ruleID: "right")]])

        let rows = DiagnosticRowMapper.rows(for: rendered, left: left, right: right)

        let removedRowIndex = try #require(rendered.rows.firstIndex { $0.oldNumber == 3 })
        #expect(rows.keys.sorted() == [removedRowIndex])
        #expect(rows[removedRowIndex]?.findings.map(\.ruleID) == ["left"])
    }

    @Test
    func `the new pane shows only the right side's findings`() throws {
        let text = "line1\nline2\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let left = SideFindings(paths: [0: "a.swift"], findings: ["a.swift": [finding(line: 1, ruleID: "left")]])
        let right = SideFindings(paths: [0: "a.swift"], findings: ["a.swift": [finding(line: 2, ruleID: "right")]])

        let rows = DiagnosticRowMapper.rows(for: rendered, left: left, right: right)

        #expect(rows.values.flatMap(\.findings).map(\.ruleID) == ["right"])
    }

    @Test
    func `an unchanged unified row shows a finding both sides report once`() throws {
        let text = "line1\nline2\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
        let both = ["a.swift": [finding(line: 2)]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: SideFindings(paths: [0: "a.swift"], findings: both),
            right: SideFindings(paths: [0: "a.swift"], findings: both))

        #expect(rows.values.map(\.count) == [1])
    }

    @Test
    func `a finding under a different file index than the row's is absent`() throws {
        let file1 = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: "x\n", newText: "x\n", language: .plain), granularity: .word)
        let file2 = PreparedDiff(
            FileDiffInput(title: "b.swift", oldText: "y\n", newText: "y\n", language: .plain), granularity: .word)
        let diff = DiffRenderer.render(
            prepared: [file1, file2], options: DiffRenderer.Options(sides: [.new]), layout: .full, withHeaders: true)
        let rendered = try #require(diff.new)
        let paths = [0: "a.swift", 1: "b.swift"]
        let findings = ["b.swift": [finding(line: 1, file: "b.swift")]]

        let rows = DiagnosticRowMapper.rows(
            for: rendered, left: .none, right: SideFindings(paths: paths, findings: findings))

        // Only the row belonging to file 1 ("b.swift") should be annotated, never file 0's row on the same line.
        for (rowIndex, row) in rows {
            #expect(rendered.rows[rowIndex].fileIndex == 1)
            #expect(row.findings.allSatisfy { $0.file == "b.swift" })
        }
        #expect(!rows.isEmpty)
    }
}
