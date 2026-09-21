package import AtelierDiagnostics
package import Foundation
import Observation

/// The window's diagnostics state: wires a ``DiagnosticsSession`` to the comparison and to ``ViewerSettings``,
/// and exposes findings grouped by file for the explorers and detail area to annotate.
@Observable
@MainActor
package final class DiagnosticsModel {
    package private(set) var findingsByFile: [String: [Finding]] = [:]
    package private(set) var runStates: [DiagnosticTool: DiagnosticsEngine.RunStatus] = [:]
    package private(set) var isRunning = false

    package var summary: DiagnosticsSummary {
        var errors = 0
        var warnings = 0
        var byTool: [DiagnosticTool: DiagnosticsSummary.ToolCounts] = [:]
        for (tool, findings) in findingsByTool {
            var counts = DiagnosticsSummary.ToolCounts(errors: 0, warnings: 0)
            for finding in findings {
                switch finding.severity {
                    case .error: counts.errors += 1
                    case .warning: counts.warnings += 1
                    case .note: break
                }
            }
            byTool[tool] = counts
            errors += counts.errors
            warnings += counts.warnings
        }
        return DiagnosticsSummary(
            errors: errors, warnings: warnings, byTool: byTool, isEmpty: errors == 0 && warnings == 0)
    }

    /// Called with every path whose findings changed, so the owner can invalidate just those rows.
    @ObservationIgnored package var onFindingsChanged: ((Set<String>) -> Void)?

    private let session: DiagnosticsSession
    private let settings: ViewerSettings
    /// Each tool's latest findings, kept separately so one tool's fresh result replaces only its own
    /// contribution to ``findingsByFile`` without disturbing another tool's still-in-flight one.
    @ObservationIgnored private var findingsByTool: [DiagnosticTool: [Finding]] = [:]
    /// The request the current comparison would run, kept so a settings change (such as re-enabling a tool)
    /// can re-run it without waiting for the next comparison.
    @ObservationIgnored private var lastRequest: DiagnosticsEngine.Request?

    package init(session: DiagnosticsSession, settings: ViewerSettings) {
        self.session = session
        self.settings = settings
        session.onUpdate = { [weak self] update in self?.apply(update) }
        session.onRunStateChanged = { [weak self] running in self?.isRunning = running }
        settings.addObserver(self) { [weak self] change in self?.settingsChanged(change) }
    }

    /// Builds a request for the tools currently enabled and hands it to the session; a comparison with no root
    /// (nothing loaded yet) or with diagnostics turned off clears whatever findings were showing instead.
    package func comparisonChanged(root: URL?, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String?) {
        guard let root else {
            lastRequest = nil
            session.cancel()
            clear()
            return
        }
        let tools = settings.toolLocations.filter(\.value.isEnabled)
        let request = DiagnosticsEngine.Request(
            root: root, files: files, corpusFingerprint: corpusFingerprint, tools: tools)
        lastRequest = request
        guard settings.diagnosticsEnabled, !tools.isEmpty else {
            session.cancel()
            clear()
            return
        }
        resetForNewRun()
        session.analyze(request)
    }

    /// Drops every finding and run state; call when diagnostics are turned off or nothing is being compared.
    package func clear() {
        findingsByTool = [:]
        runStates = [:]
        isRunning = false
        let previousPaths = Set(findingsByFile.keys)
        findingsByFile = [:]
        guard !previousPaths.isEmpty else { return }
        onFindingsChanged?(previousPaths)
    }

    private func apply(_ update: DiagnosticsSession.Update) {
        let previousPaths = Set(findingsByTool[update.result.tool]?.map(\.file) ?? [])
        findingsByTool[update.result.tool] = update.result.findings
        runStates[update.result.tool] = update.result.status
        recomputeFindingsByFile()
        let newPaths = Set(update.result.findings.map(\.file))
        onFindingsChanged?(previousPaths.union(newPaths))
    }

    private func recomputeFindingsByFile() {
        var byFile: [String: [Finding]] = [:]
        for findings in findingsByTool.values {
            for finding in findings { byFile[finding.file, default: []].append(finding) }
        }
        findingsByFile = byFile
    }

    /// Clears accumulated state ahead of a fresh run, notifying every path that is about to lose its findings.
    private func resetForNewRun() {
        findingsByTool = [:]
        runStates = [:]
        let previousPaths = Set(findingsByFile.keys)
        findingsByFile = [:]
        guard !previousPaths.isEmpty else { return }
        onFindingsChanged?(previousPaths)
    }

    /// The master toggle turning off cancels and clears; any other diagnostics change (a tool's enablement or
    /// custom path) re-runs the last known request so its effect shows up without a fresh comparison.
    private func settingsChanged(_ change: ViewerSettings.Change) {
        guard change == .diagnostics else { return }
        guard settings.diagnosticsEnabled else {
            session.cancel()
            clear()
            return
        }
        guard var request = lastRequest else { return }
        let tools = settings.toolLocations.filter(\.value.isEnabled)
        guard !tools.isEmpty else {
            session.cancel()
            clear()
            return
        }
        request.tools = tools
        lastRequest = request
        resetForNewRun()
        session.analyze(request)
    }
}

/// The current totals shown in the window's chrome: overall counts and each tool's own.
package struct DiagnosticsSummary: Equatable, Sendable {
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
}
