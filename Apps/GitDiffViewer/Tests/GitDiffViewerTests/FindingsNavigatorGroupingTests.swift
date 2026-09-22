import AtelierDiagnostics
import Testing

@testable import DiffComparison

struct FindingsNavigatorGroupingTests {
    private func finding(
        file: String, line: Int, column: Int? = nil, ruleID: String = "rule", severity: Finding.Severity = .warning
    ) -> Finding {
        Finding(
            tool: .swiftlint, ruleID: ruleID, message: "message", file: file, line: line, column: column,
            severity: severity)
    }

    @Test
    func `groups are sorted by file path`() {
        let groups = FindingsNavigatorGrouping.groups([
            "b.swift": [finding(file: "b.swift", line: 1)],
            "a.swift": [finding(file: "a.swift", line: 1)]
        ])

        #expect(groups.map(\.path) == ["a.swift", "b.swift"])
    }

    @Test
    func `a file's findings are sorted by line then column`() {
        let groups = FindingsNavigatorGrouping.groups([
            "a.swift": [
                finding(file: "a.swift", line: 3, column: 1),
                finding(file: "a.swift", line: 1, column: 5),
                finding(file: "a.swift", line: 1, column: 2)
            ]
        ])

        #expect(
            groups.first?.findings.map { ($0.line, $0.column) }.map { "\($0.0):\($0.1 ?? -1)" } == [
                "1:2", "1:5", "3:1"
            ])
    }

    @Test
    func `a file with no findings is dropped entirely`() {
        let groups = FindingsNavigatorGrouping.groups(["empty.swift": []])

        #expect(groups.isEmpty)
    }
}
