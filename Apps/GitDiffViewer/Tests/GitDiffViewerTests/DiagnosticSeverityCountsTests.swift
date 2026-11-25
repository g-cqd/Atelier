import AtelierDiagnostics
import Testing

@testable import DiffComparison

/// ``DiagnosticSeverityCounts``' tally of a file's findings, the warning and error counts a card header shows.
struct DiagnosticSeverityCountsTests {
    private func finding(_ severity: Finding.Severity) -> Finding {
        Finding(tool: .swiftlint, ruleID: "rule", message: "message", file: "A.swift", line: 1, severity: severity)
    }

    @Test
    func `counts warnings and errors separately, ignoring notes`() {
        let counts = DiagnosticSeverityCounts([finding(.warning), finding(.warning), finding(.error), finding(.note)])

        #expect(counts.warnings == 2)
        #expect(counts.errors == 1)
        #expect(!counts.isEmpty)
    }

    @Test
    func `no findings is empty`() {
        #expect(DiagnosticSeverityCounts([]).isEmpty)
    }

    @Test
    func `only notes is still empty`() {
        #expect(DiagnosticSeverityCounts([finding(.note)]).isEmpty)
    }
}
