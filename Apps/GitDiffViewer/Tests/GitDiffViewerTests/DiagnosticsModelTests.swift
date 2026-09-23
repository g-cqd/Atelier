import AemiTesting
import AtelierDiagnostics
import Foundation
import Observation
import Testing

@testable import DiffComparison

/// ``DiagnosticsModel``: merging streamed findings per tool, the summary, the changed paths it reports, and its
/// reactions to settings, over a real ``DiagnosticsSession`` and a fake runner.
@MainActor
struct DiagnosticsModelTests {
    private static let root = URL(filePath: "/repo")

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.diagnostics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private struct SUT {
        let model: DiagnosticsModel
        let settings: ViewerSettings
        let runner: FakeDiagnosticsRunner
        let spy: TaskProviderSpy
    }

    private func makeSUT(runner: FakeDiagnosticsRunner? = nil, clock: TestClock? = nil) throws -> SUT {
        let runner = runner ?? FakeDiagnosticsRunner()
        let spy = TaskProviderSpy.tolerant()
        let settings = ViewerSettings(defaults: try makeDefaults())
        settings.diagnosticsEnabled = true
        let model =
            if let clock {
                DiagnosticsModel(
                    engine: runner, settings: settings, taskProvider: spy, clock: clock, debounce: Self.debounce)
            } else {
                DiagnosticsModel(engine: runner, settings: settings, taskProvider: spy, debounce: .milliseconds(1))
            }
        return SUT(model: model, settings: settings, runner: runner, spy: spy)
    }

    private static let debounce: Duration = .milliseconds(250)

    /// Lets the debounced run of the request just made start, on the virtual clock.
    private func startRun(on clock: TestClock) async throws {
        try await clock.waitForSleepers()
        clock.advance(by: Self.debounce)
    }

    private func target(_ path: String, _ hash: String = "h") -> DiagnosticsEngine.FileTarget {
        .init(path: path, contentHash: hash, url: nil)
    }

    private func finding(_ tool: DiagnosticTool, file: String, severity: Finding.Severity = .warning) -> Finding {
        Finding(tool: tool, ruleID: "rule", message: "message", file: file, line: 1, severity: severity)
    }

    @Test
    func `findings from two tools merge by file, each tool replacing only its own contribution`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        await runner.configure(
            .arcleak, findings: [finding(.arcleak, file: "A.swift"), finding(.arcleak, file: "B.swift")])
        let sut = try makeSUT(runner: runner)

        sut.model.comparisonChanged(
            root: Self.root,
            files: [
                .init(path: "A.swift", contentHash: "a", url: nil), .init(path: "B.swift", contentHash: "b", url: nil)
            ],
            corpusFingerprint: "fp"
        )
        try await sut.spy.waitForAllTasks()

        #expect(sut.model.findingsByFile["A.swift"]?.count == 2)
        #expect(sut.model.findingsByFile["B.swift"]?.count == 1)
        #expect(sut.model.runStates[.swiftlint] == .succeeded)
        #expect(sut.model.runStates[.arcleak] == .succeeded)
    }

    @Test
    func `the summary totals errors and warnings, overall and per tool`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(
            .swiftlint,
            findings: [
                finding(.swiftlint, file: "A.swift", severity: .error),
                finding(.swiftlint, file: "A.swift", severity: .warning)
            ])
        await runner.configure(.arcleak, findings: [finding(.arcleak, file: "B.swift", severity: .warning)])
        let sut = try makeSUT(runner: runner)

        sut.model.comparisonChanged(
            root: Self.root,
            files: [
                .init(path: "A.swift", contentHash: "a", url: nil), .init(path: "B.swift", contentHash: "b", url: nil)
            ],
            corpusFingerprint: nil
        )
        try await sut.spy.waitForAllTasks()

        let summary = sut.model.summary
        #expect(summary.errors == 1)
        #expect(summary.warnings == 2)
        #expect(!summary.isEmpty)
        #expect(summary.byTool[.swiftlint] == DiagnosticsSummary.ToolCounts(errors: 1, warnings: 1))
        #expect(summary.byTool[.arcleak] == DiagnosticsSummary.ToolCounts(errors: 0, warnings: 1))
    }

    @Test
    func `onFindingsChanged reports the paths a tool's findings touched`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        let sut = try makeSUT(runner: runner)
        var changed: [Set<String>] = []
        sut.model.onFindingsChanged = { changed.append($0) }

        sut.model.comparisonChanged(
            root: Self.root, files: [.init(path: "A.swift", contentHash: "a", url: nil)], corpusFingerprint: nil)
        try await sut.spy.waitForAllTasks()

        #expect(changed.contains(["A.swift"]))
    }

    @Test
    func `turning the master toggle off cancels the run and clears findings`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        let sut = try makeSUT(runner: runner)
        sut.model.comparisonChanged(
            root: Self.root, files: [.init(path: "A.swift", contentHash: "a", url: nil)], corpusFingerprint: nil)
        try await sut.spy.waitForAllTasks()
        #expect(!sut.model.findingsByFile.isEmpty)

        sut.settings.diagnosticsEnabled = false

        #expect(sut.model.findingsByFile.isEmpty)
        #expect(!sut.model.isRunning)
    }

    @Test
    func `comparisonChanged only asks the session to run enabled tools`() async throws {
        let runner = FakeDiagnosticsRunner()
        let sut = try makeSUT(runner: runner)
        sut.settings.toolLocations = [
            .swiftlint: ToolLocation(isEnabled: true), .arcleak: ToolLocation(isEnabled: false)
        ]

        sut.model.comparisonChanged(
            root: Self.root, files: [.init(path: "A.swift", contentHash: "a", url: nil)], corpusFingerprint: nil)
        try await sut.spy.waitForAllTasks()

        let calls = await sut.runner.calls
        #expect(calls == [.swiftlint])
    }

    // MARK: - Observed summary (GDV B9)

    @Test
    func `observers of the summary hear findings land`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        let clock = TestClock()
        let sut = try makeSUT(runner: runner, clock: clock)
        let changes = CountProbe()
        withObservationTracking {
            _ = sut.model.summary
        } onChange: {
            changes.record()
        }

        sut.model.comparisonChanged(root: Self.root, files: [target("A.swift")], corpusFingerprint: "fp")
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()

        #expect(changes.count == 1)
        #expect(sut.model.summary.warnings == 1)
    }

    @Test
    func `observers of the summary hear findings clear`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        let clock = TestClock()
        let sut = try makeSUT(runner: runner, clock: clock)
        sut.model.comparisonChanged(root: Self.root, files: [target("A.swift")], corpusFingerprint: "fp")
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()
        let changes = CountProbe()
        withObservationTracking {
            _ = sut.model.summary
        } onChange: {
            changes.record()
        }

        sut.settings.diagnosticsEnabled = false

        #expect(changes.count == 1)
        #expect(sut.model.summary.isEmpty)
    }

    // MARK: - Unchanged requests and per-tool replacement (GDV S9)

    @Test
    func `an identical request keeps the findings and runs no tool again`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        let clock = TestClock()
        let sut = try makeSUT(runner: runner, clock: clock)
        sut.model.comparisonChanged(root: Self.root, files: [target("A.swift")], corpusFingerprint: "fp")
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()
        let callsBefore = await runner.calls.count

        sut.model.comparisonChanged(root: Self.root, files: [target("A.swift")], corpusFingerprint: "fp")
        try await sut.spy.waitForAllTasks()

        #expect(sut.model.findingsByFile["A.swift"]?.count == 1)
        #expect(await runner.calls.count == callsBefore)
    }

    @Test
    func `a tool's new result replaces only that tool's findings`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        await runner.configure(.arcleak, findings: [finding(.arcleak, file: "B.swift")])
        let clock = TestClock()
        let sut = try makeSUT(runner: runner, clock: clock)
        sut.model.comparisonChanged(
            root: Self.root, files: [target("A.swift"), target("B.swift")], corpusFingerprint: "one")
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "C.swift")])
        let arcleakGate = TaskGate()
        await runner.hold(.arcleak, until: arcleakGate)
        let swiftlintLanded = AsyncProbe<Set<String>>()
        sut.model.onFindingsChanged = { paths in
            if paths.contains("C.swift") { swiftlintLanded.send(paths) }
        }

        sut.model.comparisonChanged(
            root: Self.root, files: [target("A.swift"), target("B.swift"), target("C.swift")],
            corpusFingerprint: "two")
        try await startRun(on: clock)
        _ = try await swiftlintLanded.next()

        #expect(sut.model.findingsByFile["A.swift"] == nil)
        #expect(sut.model.findingsByFile["B.swift"]?.map(\.tool) == [.arcleak])
        #expect(sut.model.findingsByFile["C.swift"]?.map(\.tool) == [.swiftlint])
        arcleakGate.open()
        try await sut.spy.waitForAllTasks()
    }

    @Test
    func `a tool turned off loses its findings at once`() async throws {
        let runner = FakeDiagnosticsRunner()
        await runner.configure(.swiftlint, findings: [finding(.swiftlint, file: "A.swift")])
        await runner.configure(.arcleak, findings: [finding(.arcleak, file: "B.swift")])
        let clock = TestClock()
        let sut = try makeSUT(runner: runner, clock: clock)
        sut.model.comparisonChanged(
            root: Self.root, files: [target("A.swift"), target("B.swift")], corpusFingerprint: "fp")
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()

        sut.settings.toolLocations[.arcleak] = ToolLocation(isEnabled: false)

        #expect(sut.model.findingsByFile["B.swift"] == nil)
        #expect(sut.model.findingsByFile["A.swift"]?.count == 1)
        try await startRun(on: clock)
        try await sut.spy.waitForAllTasks()
    }
}

/// A ``DiagnosticsRunning`` returning preconfigured findings for each tool, at once or once the tool's gate opens.
private actor FakeDiagnosticsRunner: DiagnosticsRunning {
    private var findingsByTool: [DiagnosticTool: [Finding]] = [:]
    private var gates: [DiagnosticTool: TaskGate] = [:]
    private(set) var calls: [DiagnosticTool] = []

    func configure(_ tool: DiagnosticTool, findings: [Finding]) {
        findingsByTool[tool] = findings
    }

    /// Holds every later run of `tool` until `gate` opens.
    func hold(_ tool: DiagnosticTool, until gate: TaskGate) {
        gates[tool] = gate
    }

    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        calls.append(tool)
        let findings = findingsByTool[tool] ?? []
        if let gate = gates[tool] { try await gate.wait() }
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: findings, status: .succeeded, duration: .zero, fromCache: false)
    }
}
