package import AemiCore
package import AtelierDiagnostics
package import Foundation
import Observation

/// The window's diagnostics state: wires a ``DiagnosticsSession`` to the comparison and to ``ViewerSettings``,
/// and exposes findings grouped by file for the explorers and detail area to annotate.
///
/// ``DiagnosticsSession`` is core-tier and caller-driven (no stored task, no debounce): this model is the caller,
/// so it owns the debounce (250 ms by default, coalescing a burst of comparison/settings changes into one run),
/// the cancel-and-replace generation that supersedes a still-running analysis, and the task that drives it all
/// through its own ``TaskProvider``.
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
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let debounce: Duration
    /// Each tool's latest findings, kept separately so one tool's fresh result replaces only its own
    /// contribution to ``findingsByFile`` without disturbing another tool's still-in-flight one.
    @ObservationIgnored private var findingsByTool: [DiagnosticTool: [Finding]] = [:]
    /// The request the current comparison would run, kept so a settings change (such as re-enabling a tool)
    /// can re-run it without waiting for the next comparison.
    @ObservationIgnored private var lastRequest: DiagnosticsEngine.Request?
    /// Bumped by every ``run(_:)`` and ``cancel()``; a debounced or in-flight run whose captured generation no
    /// longer matches has already been superseded or cancelled, and its updates are dropped when they land.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - engine: Runs each enabled tool; the production caller passes a ``DiagnosticsEngine``, a test a fake.
    ///   - settings: Supplies which tools are enabled and whether diagnostics run at all.
    ///   - taskProvider: Spawns the debounce and the analysis it guards.
    ///   - clock: Drives the debounce; a test injects a virtual one.
    ///   - debounce: Trailing coalesce before a run starts, kept under ``RepositoryFreshness``'s tree debounce so
    ///     a save's diagnostics never race its freshness reload.
    package init(
        engine: any DiagnosticsRunning, settings: ViewerSettings, taskProvider: any TaskProvider,
        clock: any Clock<Duration> = ContinuousClock(), debounce: Duration = .milliseconds(250)
    ) {
        self.session = DiagnosticsSession(engine: engine)
        self.settings = settings
        self.taskProvider = taskProvider
        self.clock = clock
        self.debounce = debounce
        settings.addObserver(self) { [weak self] change in self?.settingsChanged(change) }
    }

    /// Builds a request for the tools currently enabled and hands it to the session; a comparison with no root
    /// (nothing loaded yet) or with diagnostics turned off clears whatever findings were showing instead.
    package func comparisonChanged(root: URL?, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String?) {
        guard let root else {
            lastRequest = nil
            cancel()
            clear()
            return
        }
        let tools = settings.toolLocations.filter(\.value.isEnabled)
        let request = DiagnosticsEngine.Request(
            root: root, files: files, corpusFingerprint: corpusFingerprint, tools: tools)
        lastRequest = request
        guard settings.diagnosticsEnabled, !tools.isEmpty else {
            cancel()
            clear()
            return
        }
        resetForNewRun()
        run(request)
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

    /// Validates `generation` and applies `update` in the same actor-isolated step, so a run superseded between
    /// the check and the mutation (by a new comparison or ``cancel()``) can never repopulate cleared findings.
    private func apply(_ update: DiagnosticsSession.Update, generation: Int) {
        guard self.generation == generation else { return }
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
            cancel()
            clear()
            return
        }
        guard var request = lastRequest else { return }
        let tools = settings.toolLocations.filter(\.value.isEnabled)
        guard !tools.isEmpty else {
            cancel()
            clear()
            return
        }
        request.tools = tools
        lastRequest = request
        resetForNewRun()
        run(request)
    }

    /// Debounces, cancels whatever run is still in flight, and hands `request` to the session, applying each
    /// tool's update as it streams back. The debounce and cancel-and-replace are this model's own — the session
    /// itself is caller-driven and does neither.
    private func run(_ request: DiagnosticsEngine.Request) {
        task?.cancel()
        generation &+= 1
        let generation = generation
        let session = session
        let clock = clock
        let debounce = debounce

        task = taskProvider.task { [weak self] in
            try? await clock.sleep(for: debounce)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.isRunning = true
            await session.analyze(request) { [weak self] update in
                await self?.apply(update, generation: generation)
            }
            guard self.generation == generation else { return }
            self.isRunning = false
        }
    }

    /// Stops the current run (debounced or in flight) without starting another; no further updates are applied
    /// for it.
    private func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
        isRunning = false
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
