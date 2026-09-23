package import AemiCore
package import AtelierDiagnostics
package import Foundation
import Observation

/// The window's diagnostics state: wires a ``DiagnosticsSession`` to the comparison and to ``ViewerSettings``,
/// and exposes findings grouped by file. It owns the debounce and the cancel-and-replace that the caller-driven
/// session leaves to its caller.
@Observable
@MainActor
package final class DiagnosticsModel {
    package private(set) var findingsByFile: [String: [Finding]] = [:]
    package private(set) var runStates: [DiagnosticTool: DiagnosticsEngine.RunStatus] = [:]
    package private(set) var isRunning = false
    /// The totals the window's chrome shows. Stored, not derived from the unobserved per-tool findings, so the
    /// toolbar and the status bar redraw as soon as findings land or clear (GDV B9).
    package private(set) var summary = DiagnosticsSummary.empty

    /// Called with every path whose findings changed, so the owner can invalidate just those rows.
    @ObservationIgnored package var onFindingsChanged: ((Set<String>) -> Void)?
    /// The finding the Findings list last opened, until the window scrolls to its line.
    @ObservationIgnored package var pendingReveal: FindingReveal?

    private let session: DiagnosticsSession
    private let settings: ViewerSettings
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let debounce: Duration
    /// Each tool's latest findings, so one tool's result replaces only its own share of ``findingsByFile``.
    @ObservationIgnored private var findingsByTool: [DiagnosticTool: [Finding]] = [:]
    /// The current comparison's request, re-run when a diagnostics setting changes.
    @ObservationIgnored private var lastRequest: DiagnosticsEngine.Request?
    /// Bumped by every ``run(_:)`` and ``cancel()``; updates from an older generation are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - engine: Runs each enabled tool.
    ///   - settings: Supplies which tools are enabled and whether diagnostics run at all.
    ///   - taskProvider: Spawns the debounce and the analysis it guards.
    ///   - clock: Drives the debounce; a test injects a virtual one.
    ///   - debounce: Trailing coalesce before a run starts.
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

    /// Builds a request for the enabled tools and runs it; a nil `root`, diagnostics turned off or no enabled tool
    /// clears the findings instead. A request equal to the one already run, or running, keeps what is shown and asks
    /// no tool again, so a reload of an unchanged changeset neither blinks the squiggles nor re-lints (GDV S9).
    package func comparisonChanged(root: URL?, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String?) {
        guard let root else {
            lastRequest = nil
            cancel()
            clear()
            return
        }
        let tools = settings.toolLocations.filter(\.value.isEnabled)
        request(
            DiagnosticsEngine.Request(root: root, files: files, corpusFingerprint: corpusFingerprint, tools: tools))
    }

    /// Runs `request` unless diagnostics are off, it enables no tool, or it is the request already run or running.
    private func request(_ request: DiagnosticsEngine.Request) {
        let isUnchanged = request == lastRequest && task != nil
        let isAnotherRoot = lastRequest.map { $0.root != request.root } ?? false
        lastRequest = request
        guard settings.diagnosticsEnabled, !request.tools.isEmpty else {
            cancel()
            clear()
            return
        }
        guard !isUnchanged else { return }
        // Another repository's findings mean nothing here; within one, each tool's stay until it reports again.
        if isAnotherRoot { clear() }
        dropFindings(ofToolsOutside: Set(request.tools.keys))
        run(request)
    }

    /// Drops every finding and run state; call when diagnostics are turned off or nothing is being compared.
    package func clear() {
        findingsByTool = [:]
        runStates = [:]
        isRunning = false
        let previousPaths = Set(findingsByFile.keys)
        recomputeFindings()
        guard !previousPaths.isEmpty else { return }
        onFindingsChanged?(previousPaths)
    }

    /// Checks `generation` and applies `update` in one isolated step, so a superseded run never repopulates cleared
    /// findings. The tool's result replaces its own findings and nothing else.
    private func apply(_ update: DiagnosticsSession.Update, generation: Int) {
        guard self.generation == generation else { return }
        let previousPaths = Set(findingsByTool[update.result.tool]?.map(\.file) ?? [])
        findingsByTool[update.result.tool] = update.result.findings
        runStates[update.result.tool] = update.result.status
        recomputeFindings()
        let newPaths = Set(update.result.findings.map(\.file))
        onFindingsChanged?(previousPaths.union(newPaths))
    }

    /// Rebuilds ``findingsByFile`` and ``summary`` from each tool's latest findings.
    private func recomputeFindings() {
        var byFile: [String: [Finding]] = [:]
        for findings in findingsByTool.values {
            for finding in findings { byFile[finding.file, default: []].append(finding) }
        }
        findingsByFile = byFile
        let updated = DiagnosticsSummary(findingsByTool)
        if updated != summary { summary = updated }
    }

    /// Drops the findings and run states of every tool a new run will not run, notifying the paths they covered;
    /// the other tools keep theirs until their new result replaces them.
    private func dropFindings(ofToolsOutside tools: Set<DiagnosticTool>) {
        let dropped = findingsByTool.keys.filter { !tools.contains($0) }
        let staleStates = runStates.keys.filter { !tools.contains($0) }
        guard !dropped.isEmpty || !staleStates.isEmpty else { return }
        let paths = Set(dropped.flatMap { findingsByTool[$0]?.map(\.file) ?? [] })
        for tool in dropped { findingsByTool[tool] = nil }
        for tool in staleStates { runStates[tool] = nil }
        recomputeFindings()
        guard !paths.isEmpty else { return }
        onFindingsChanged?(paths)
    }

    /// Turning diagnostics off cancels and clears; any other diagnostics change re-runs the last request with the
    /// tools now enabled.
    private func settingsChanged(_ change: ViewerSettings.Change) {
        guard change == .diagnostics else { return }
        guard var request = lastRequest else {
            if !settings.diagnosticsEnabled {
                cancel()
                clear()
            }
            return
        }
        request.tools = settings.toolLocations.filter(\.value.isEnabled)
        self.request(request)
    }

    /// Replaces any run in flight with `request` after the debounce, applying each tool's update as it streams back.
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
