package import AemiCore
package import AtelierDiagnostics
package import Foundation
import Observation

/// The window's diagnostics state: wires a ``DiagnosticsSession`` to the comparison's two sides and to
/// ``ViewerSettings``, and exposes each side's findings grouped by file. It owns the debounce and the
/// cancel-and-replace that the caller-driven session leaves to its caller.
///
/// Each side the analyzed-sides setting includes runs on its own files (DIAG-08, decision D12): a folder in place, a
/// git ref exported first into a private folder, only in a repository the user trusts. A side's findings stay its
/// own, so the left side's never show on the right side's rows or the other way round.
@Observable
@MainActor
package final class DiagnosticsModel {
    /// The right side's findings, by right-side path.
    package private(set) var findingsByFile: [String: [Finding]] = [:]
    /// The left side's findings, by left-side path; empty while the left side is not analyzed.
    package private(set) var leftFindingsByFile: [String: [Finding]] = [:]
    /// Each tool's last outcome; a failure, a missing tool or a skip on one side shows over a success on the other.
    package private(set) var runStates: [DiagnosticTool: DiagnosticsEngine.RunStatus] = [:]
    package private(set) var isRunning = false
    /// The totals the window's chrome shows, over both sides. Stored, not derived from the unobserved per-tool
    /// findings, so the toolbar and the status bar redraw as soon as findings land or clear (GDV B9).
    package private(set) var summary = DiagnosticsSummary.empty

    /// Called with every path whose findings changed, so the owner can invalidate just those rows.
    @ObservationIgnored package var onFindingsChanged: ((Set<String>) -> Void)?
    /// The finding the Findings list last opened, until the window scrolls to its line.
    @ObservationIgnored package var pendingReveal: FindingReveal?
    /// The user's trust decisions: a side that is a git ref is analyzed only in a repository the user trusts, and in
    /// none while no store is attached.
    @ObservationIgnored package var trust: RepositoryTrust?
    /// Exports a ref side's tree for its analysis; with none, only folders are analyzed.
    @ObservationIgnored package var treeExporter: (any DiagnosticsTreeExporting)?

    private let session: DiagnosticsSession
    private let settings: ViewerSettings
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let debounce: Duration
    /// Each side's and each tool's latest findings, so one tool's result replaces only its own share.
    @ObservationIgnored private var findingsBySide: [DiagnosticsSide: [DiagnosticTool: [Finding]]] = [:]
    @ObservationIgnored private var statusesBySide: [DiagnosticsSide: [DiagnosticTool: DiagnosticsEngine.RunStatus]] =
        [:]
    /// What the comparison's sides offer, planned again when a diagnostics setting changes.
    @ObservationIgnored private var sides = DiagnosticsSides()
    /// The plan run or running.
    @ObservationIgnored private var lastPlan: DiagnosticsPlan?
    /// Bumped by every ``run(_:)`` and ``cancel()``; updates from an older generation are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - engine: Runs each enabled tool.
    ///   - settings: Supplies which tools are enabled, which sides are analyzed, and whether diagnostics run at all.
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

    /// Offers the right side as the folder at `root` with the changed Swift `files`, as a comparison whose only
    /// readable side is its working tree does; a nil `root` offers nothing, which clears the findings.
    package func comparisonChanged(root: URL?, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String?) {
        comparisonChanged(
            DiagnosticsSides(
                right: root.map {
                    DiagnosticsSideTarget(content: .directory($0), files: files, corpusFingerprint: corpusFingerprint)
                }))
    }

    /// Plans a run over what each side offers, under the analyzed-sides setting and the user's trust, and runs it. A
    /// plan with nothing to do clears the findings, a changeset without a Swift file among them (DIAG-01); a plan
    /// equal to the one run or running keeps what is shown and asks no tool again, so a reload of an unchanged
    /// changeset neither blinks the squiggles nor re-lints (GDV S9).
    package func comparisonChanged(_ sides: DiagnosticsSides) {
        self.sides = sides
        request(plan())
    }

    private func plan() -> DiagnosticsPlan {
        let trust = trust
        return DiagnosticsPlan(
            sides: sides, mode: settings.analyzedSides, tools: settings.toolLocations.filter(\.value.isEnabled),
            canExport: treeExporter != nil, isTrusted: { trust?.isTrusted($0) ?? false })
    }

    /// Runs `plan` unless diagnostics are off, it has nothing to do, or it is the plan run or running.
    private func request(_ plan: DiagnosticsPlan) {
        let isUnchanged = plan == lastPlan && task != nil
        let readsElsewhere = lastPlan.map { $0.locations.isDisjoint(with: plan.locations) } ?? false
        lastPlan = plan
        guard settings.diagnosticsEnabled, !plan.isEmpty else {
            cancel()
            clear()
            return
        }
        guard !isUnchanged else { return }
        // Another comparison's findings mean nothing here; within one, each tool's stay until it reports again.
        if readsElsewhere { clear() }
        dropFindings(outside: plan)
        run(plan)
    }

    /// Drops every finding and run state; call when diagnostics are turned off or nothing is being compared.
    package func clear() {
        let previousPaths = Set(findingsByFile.keys).union(leftFindingsByFile.keys)
        findingsBySide = [:]
        statusesBySide = [:]
        isRunning = false
        recomputeFindings()
        guard !previousPaths.isEmpty else { return }
        onFindingsChanged?(previousPaths)
    }

    /// Checks `generation` and applies `update` to `side` in one isolated step, so a superseded run never
    /// repopulates cleared findings. The tool's result replaces its own findings on that side and nothing else.
    private func apply(_ update: DiagnosticsSession.Update, side: DiagnosticsSide, generation: Int) {
        guard self.generation == generation else { return }
        let tool = update.result.tool
        let previousPaths = Set(findingsBySide[side]?[tool]?.map(\.file) ?? [])
        findingsBySide[side, default: [:]][tool] = update.result.findings
        statusesBySide[side, default: [:]][tool] = update.result.status
        recomputeFindings()
        onFindingsChanged?(previousPaths.union(update.result.findings.map(\.file)))
    }

    /// Rebuilds each side's findings by file, the merged run states and the summary from the per-tool findings.
    private func recomputeFindings() {
        let right = Self.byFile(findingsBySide[.right] ?? [:])
        if right != findingsByFile { findingsByFile = right }
        let left = Self.byFile(findingsBySide[.left] ?? [:])
        if left != leftFindingsByFile { leftFindingsByFile = left }
        var states: [DiagnosticTool: DiagnosticsEngine.RunStatus] = [:]
        var byTool: [DiagnosticTool: [Finding]] = [:]
        for side in DiagnosticsSide.allCases {
            for (tool, status) in statusesBySide[side] ?? [:] {
                states[tool] = states[tool].map { Self.moreTelling($0, status) } ?? status
            }
            for (tool, findings) in findingsBySide[side] ?? [:] { byTool[tool, default: []] += findings }
        }
        if states != runStates { runStates = states }
        let updated = DiagnosticsSummary(byTool)
        if updated != summary { summary = updated }
    }

    private static func byFile(_ findingsByTool: [DiagnosticTool: [Finding]]) -> [String: [Finding]] {
        var byFile: [String: [Finding]] = [:]
        for findings in findingsByTool.values {
            for finding in findings { byFile[finding.file, default: []].append(finding) }
        }
        return byFile
    }

    /// Of one tool's outcomes on the two sides, the one worth showing: a failure, then a missing tool, then a skip,
    /// then a success.
    private static func moreTelling(
        _ lhs: DiagnosticsEngine.RunStatus, _ rhs: DiagnosticsEngine.RunStatus
    ) -> DiagnosticsEngine.RunStatus {
        func rank(_ status: DiagnosticsEngine.RunStatus) -> Int {
            switch status {
                case .failed: 3
                case .toolMissing: 2
                case .skipped: 1
                case .succeeded: 0
            }
        }
        return rank(rhs) > rank(lhs) ? rhs : lhs
    }

    /// Drops the findings and run states of every side `plan` does not analyze and of every tool it does not run,
    /// notifying the paths they covered; the rest stay until their new result replaces them.
    private func dropFindings(outside plan: DiagnosticsPlan) {
        let sides = Set(plan.runs.map(\.side))
        let tools = Set(plan.tools.keys)
        var droppedPaths: Set<String> = []
        var dropped = false
        for side in DiagnosticsSide.allCases {
            for (tool, findings) in findingsBySide[side] ?? [:] where !sides.contains(side) || !tools.contains(tool) {
                droppedPaths.formUnion(findings.map(\.file))
                findingsBySide[side]?[tool] = nil
                dropped = true
            }
            for tool in (statusesBySide[side] ?? [:]).keys where !sides.contains(side) || !tools.contains(tool) {
                statusesBySide[side]?[tool] = nil
                dropped = true
            }
        }
        guard dropped else { return }
        recomputeFindings()
        guard !droppedPaths.isEmpty else { return }
        onFindingsChanged?(droppedPaths)
    }

    /// Turning diagnostics off cancels and clears; any other diagnostics change, a tool toggled or the analyzed
    /// sides, plans the run again.
    private func settingsChanged(_ change: ViewerSettings.Change) {
        guard change == .diagnostics else { return }
        request(plan())
    }

    /// Replaces any run in flight with `plan` after the debounce: each side in turn, the right one first, each tool's
    /// update applied as it streams back.
    private func run(_ plan: DiagnosticsPlan) {
        task?.cancel()
        generation &+= 1
        let generation = generation
        let session = session
        let clock = clock
        let debounce = debounce
        let exporter = treeExporter

        task = taskProvider.task { [weak self] in
            try? await clock.sleep(for: debounce)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.isRunning = true
            for run in plan.runs {
                guard !Task.isCancelled else { return }
                await self.analyze(run, tools: plan.tools, session: session, exporter: exporter, generation: generation)
            }
            guard self.generation == generation else { return }
            self.isRunning = false
        }
    }

    /// Analyzes one side: a folder in place, a ref's tree exported into a private folder for as long as its tools
    /// need it, and answered from the engine's cache by tree when that tree was analyzed before.
    private func analyze(
        _ run: DiagnosticsPlan.SideRun, tools: [DiagnosticTool: ToolLocation], session: DiagnosticsSession,
        exporter: (any DiagnosticsTreeExporting)?, generation: Int
    ) async {
        let side = run.side
        let target = run.target
        switch target.content {
            case .directory(let root):
                let request = DiagnosticsEngine.Request(
                    root: root, files: target.files, corpusFingerprint: target.corpusFingerprint, tools: tools)
                await session.analyze(request) { [weak self] update in
                    await self?.apply(update, side: side, generation: generation)
                }
            case .ref(let repository, let ref):
                guard let exporter else { return }
                let tree: String
                do {
                    tree = try await exporter.treeID(of: ref, in: repository)
                } catch is CancellationError {
                    return
                } catch {
                    fail(tools.keys, on: side, because: "\(ref) could not be read: \(error)", generation: generation)
                    return
                }
                let request = DiagnosticsEngine.Request(
                    root: repository, files: target.files, corpusFingerprint: tree, tools: tools,
                    contentIdentity: "tree:\(tree)")
                await session.analyze(request, materializingWith: exporter.materializer(for: tree, in: repository)) {
                    [weak self] update in
                    await self?.apply(update, side: side, generation: generation)
                }
        }
    }

    /// Reports every tool of `tools` as failed on `side`, when the side itself could not be read.
    private func fail(
        _ tools: some Collection<DiagnosticTool>, on side: DiagnosticsSide, because reason: String, generation: Int
    ) {
        for (index, tool) in tools.enumerated() {
            let result = DiagnosticsEngine.ToolResult(
                tool: tool, findings: [], status: .failed(reason), duration: .zero, fromCache: false)
            apply(.init(result: result, isLast: index == tools.count - 1), side: side, generation: generation)
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
