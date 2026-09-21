import AtelierDiagnostics
import Testing

@testable import DiffComparison

/// ``DiagnosticsBreakdown``'s lines: the status bar and toolbar's `.help()` text.
struct DiagnosticsBreakdownTests {
    private func summary(_ byTool: [DiagnosticTool: DiagnosticsSummary.ToolCounts]) -> DiagnosticsSummary {
        let errors = byTool.values.reduce(0) { $0 + $1.errors }
        let warnings = byTool.values.reduce(0) { $0 + $1.warnings }
        return DiagnosticsSummary(
            errors: errors, warnings: warnings, byTool: byTool, isEmpty: errors == 0 && warnings == 0)
    }

    @Test
    func `one line per tool with findings, counts pluralized`() {
        let lines = DiagnosticsBreakdown.lines(
            summary: summary([.swiftlint: .init(errors: 1, warnings: 2)]), runStates: [:])

        #expect(lines == ["SwiftLint — 2 warnings, 1 error"])
    }

    @Test
    func `a single finding is not pluralized`() {
        let lines = DiagnosticsBreakdown.lines(
            summary: summary([.swiftlint: .init(errors: 0, warnings: 1)]), runStates: [:])

        #expect(lines == ["SwiftLint — 1 warning"])
    }

    @Test
    func `a tool with no findings gets no line of its own`() {
        let lines = DiagnosticsBreakdown.lines(
            summary: summary([.swiftlint: .init(errors: 0, warnings: 0)]), runStates: [:])

        #expect(lines.isEmpty)
    }

    @Test
    func `a missing, failed or skipped tool gets a line even without findings`() {
        let lines = DiagnosticsBreakdown.lines(
            summary: summary([:]),
            runStates: [
                .swiftlint: .toolMissing, .arcleak: .failed("crashed"), .dolly: .skipped("cache miss")
            ])

        #expect(lines.contains("SwiftLint — not found"))
        #expect(lines.contains("arcleak — failed (crashed)"))
        #expect(lines.contains("dolly — skipped (cache miss)"))
    }

    @Test
    func `a succeeded tool with no findings gets no line`() {
        let lines = DiagnosticsBreakdown.lines(summary: summary([:]), runStates: [.swiftlint: .succeeded])

        #expect(lines.isEmpty)
    }
}
