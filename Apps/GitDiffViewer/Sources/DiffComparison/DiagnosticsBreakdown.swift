package import AtelierDiagnostics

/// The lines a status bar or toolbar breakdown shows for the current diagnostics run: one per tool that reported
/// findings, then one for each tool diagnostics tried but could not get a clean answer from. Pure so the status
/// bar's `.help()` text can be tested without a view.
package enum DiagnosticsBreakdown {
    package static func lines(summary: DiagnosticsSummary, runStates: [DiagnosticTool: DiagnosticsEngine.RunStatus])
        -> [String]
    {
        var lines: [String] = []
        for tool in DiagnosticTool.allCases {
            guard let counts = summary.byTool[tool], counts.errors + counts.warnings > 0 else { continue }
            lines.append("\(tool.displayName) — \(countsText(counts))")
        }
        for tool in DiagnosticTool.allCases {
            switch runStates[tool] {
                case .toolMissing: lines.append("\(tool.displayName) — not found")
                case .failed(let reason): lines.append("\(tool.displayName) — failed (\(reason))")
                case .skipped(let reason): lines.append("\(tool.displayName) — skipped (\(reason))")
                case .succeeded, nil: break
            }
        }
        return lines
    }

    private static func countsText(_ counts: DiagnosticsSummary.ToolCounts) -> String {
        var parts: [String] = []
        if counts.warnings > 0 { parts.append("\(counts.warnings) warning\(counts.warnings == 1 ? "" : "s")") }
        if counts.errors > 0 { parts.append("\(counts.errors) error\(counts.errors == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}
