package import AtelierDiagnostics

/// The current totals shown in the window's chrome: overall counts and each tool's own.
package struct DiagnosticsSummary: Equatable, Sendable {
    /// No finding at all.
    package static let empty = DiagnosticsSummary(errors: 0, warnings: 0, byTool: [:], isEmpty: true)

    package struct ToolCounts: Equatable, Sendable {
        package var errors: Int
        package var warnings: Int

        package init(errors: Int, warnings: Int) {
            self.errors = errors
            self.warnings = warnings
        }
    }

    package var errors: Int
    package var warnings: Int
    package var byTool: [DiagnosticTool: ToolCounts]
    package var isEmpty: Bool

    package init(errors: Int, warnings: Int, byTool: [DiagnosticTool: ToolCounts], isEmpty: Bool) {
        self.errors = errors
        self.warnings = warnings
        self.byTool = byTool
        self.isEmpty = isEmpty
    }

    /// The totals of `findingsByTool`, overall and per tool; notes count toward neither.
    init(_ findingsByTool: [DiagnosticTool: [Finding]]) {
        var byTool: [DiagnosticTool: ToolCounts] = [:]
        for (tool, findings) in findingsByTool {
            byTool[tool] = ToolCounts(
                errors: findings.count { $0.severity == .error }, warnings: findings.count { $0.severity == .warning })
        }
        let errors = byTool.values.reduce(0) { $0 + $1.errors }
        let warnings = byTool.values.reduce(0) { $0 + $1.warnings }
        self.init(errors: errors, warnings: warnings, byTool: byTool, isEmpty: errors == 0 && warnings == 0)
    }
}
