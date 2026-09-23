import AemiTesting
import AtelierDiagnostics
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// Which sides the analyzers run on (DIAG-08, decision D12): the plan the analyzed-sides setting, the changeset and
/// the user's trust make, each side's findings kept on its own side, and a ref side exported before it runs.
@MainActor
struct DiagnosticsSidesTests {
    private static let leftRoot = URL(filePath: "/left", directoryHint: .isDirectory)
    private static let rightRoot = URL(filePath: "/right", directoryHint: .isDirectory)
    private static let tools: [DiagnosticTool: ToolLocation] = [.swiftlint: ToolLocation()]
    private static let debounce: Duration = .milliseconds(250)

    private static func folder(_ root: URL, files: [String] = ["A.swift"]) -> DiagnosticsSideTarget {
        DiagnosticsSideTarget(
            content: .directory(root),
            files: files.map { .init(path: $0, contentHash: "h", url: root.appending(path: $0)) },
            corpusFingerprint: "fp")
    }

    private static func ref(_ repository: URL, _ ref: String = "HEAD") -> DiagnosticsSideTarget {
        DiagnosticsSideTarget(
            content: .ref(repository: repository, ref: ref),
            files: [.init(path: "A.swift", contentHash: "h", url: nil)],
            corpusFingerprint: "fp")
    }

    private static func plan(
        _ sides: DiagnosticsSides, mode: AnalyzedSides, canExport: Bool = true, trusted: Bool = true
    ) -> DiagnosticsPlan {
        DiagnosticsPlan(sides: sides, mode: mode, tools: tools, canExport: canExport, isTrusted: { _ in trusted })
    }

    // MARK: - The plan

    @Test
    func `the default mode plans the right side only`() {
        let plan = Self.plan(
            .init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)), mode: .rightOnly)

        #expect(plan.runs.map(\.side) == [.right])
    }

    @Test
    func `left only plans the left side only`() {
        let plan = Self.plan(
            .init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)), mode: .leftOnly)

        #expect(plan.runs.map(\.side) == [.left])
    }

    @Test
    func `both plans each side, the right one first`() {
        let plan = Self.plan(.init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)), mode: .both)

        #expect(plan.runs.map(\.side) == [.right, .left])
    }

    @Test
    func `none plans no side`() {
        let plan = Self.plan(.init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)), mode: .none)

        #expect(plan.isEmpty)
    }

    @Test
    func `a side without a changed Swift file is not planned`() {
        let plan = Self.plan(.init(right: Self.folder(Self.rightRoot, files: [])), mode: .rightOnly)

        #expect(plan.isEmpty)
    }

    @Test
    func `a ref side is not planned in a repository the user does not trust, whatever the mode`() {
        let plan = Self.plan(
            .init(left: Self.ref(Self.leftRoot), right: Self.folder(Self.rightRoot)), mode: .both, trusted: false)

        #expect(plan.runs.map(\.side) == [.right])
    }

    @Test
    func `a ref side is not planned without a way to export it`() {
        let plan = Self.plan(.init(left: Self.ref(Self.leftRoot)), mode: .leftOnly, canExport: false)

        #expect(plan.isEmpty)
    }

    // MARK: - The model

    private struct SUT {
        let model: DiagnosticsModel
        let settings: ViewerSettings
        let runner: SideRecordingRunner
        let exporter: RecordingExporter
        let clock: TestClock
        let spy: TaskProviderSpy
    }

    private func makeSUT(mode: AnalyzedSides, findings: [URL: [Finding]] = [:]) throws -> SUT {
        let name = "GitDiffViewerTests.sides.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let settings = ViewerSettings(defaults: defaults)
        settings.diagnosticsEnabled = true
        settings.analyzedSides = mode
        settings.toolLocations = Self.tools
        let runner = SideRecordingRunner(findingsByRoot: findings)
        let clock = TestClock()
        let spy = TaskProviderSpy.tolerant()
        let model = DiagnosticsModel(
            engine: runner, settings: settings, taskProvider: spy, clock: clock, debounce: Self.debounce)
        let exporter = RecordingExporter()
        model.treeExporter = exporter
        model.trust = RepositoryTrust(defaults: defaults)
        return SUT(model: model, settings: settings, runner: runner, exporter: exporter, clock: clock, spy: spy)
    }

    private func finish(_ sut: SUT) async throws {
        try await sut.clock.waitForSleepers()
        sut.clock.advance(by: Self.debounce)
        try await sut.spy.waitForAllTasks()
    }

    private static func finding(line: Int) -> Finding {
        Finding(tool: .swiftlint, ruleID: "rule", message: "message", file: "A.swift", line: line, severity: .warning)
    }

    @Test
    func `each side's findings stay on their own side`() async throws {
        let sut = try makeSUT(
            mode: .both,
            findings: [Self.leftRoot: [Self.finding(line: 1)], Self.rightRoot: [Self.finding(line: 2)]])

        sut.model.comparisonChanged(.init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)))
        try await finish(sut)

        #expect(sut.model.leftFindingsByFile["A.swift"]?.map(\.line) == [1])
        #expect(sut.model.findingsByFile["A.swift"]?.map(\.line) == [2])
        #expect(sut.model.summary.warnings == 2)
    }

    @Test
    func `a ref side in a trusted repository is analyzed in the folder its tree was exported to`() async throws {
        let repository = try TrustedRepository()
        defer { repository.remove() }
        let sut = try makeSUT(mode: .leftOnly, findings: [RecordingExporter.folder: [Self.finding(line: 3)]])
        repository.trust(in: try #require(sut.model.trust))

        sut.model.comparisonChanged(.init(left: Self.ref(repository.root, "main")))
        try await finish(sut)

        let request = try #require(await sut.runner.requests.first)
        #expect(request.root == RecordingExporter.folder)
        #expect(request.contentIdentity == "tree:tree-main")
        #expect(sut.model.leftFindingsByFile["A.swift"]?.map(\.line) == [3])
    }

    @Test
    func `a ref side in an untrusted repository exports nothing, and only the working tree runs`() async throws {
        let repository = try TrustedRepository()
        defer { repository.remove() }
        let sut = try makeSUT(mode: .both)

        sut.model.comparisonChanged(.init(left: Self.ref(repository.root), right: Self.folder(Self.rightRoot)))
        try await finish(sut)

        #expect(await sut.runner.requests.map(\.root) == [Self.rightRoot])
        #expect(sut.exporter.materializations == 0)
    }

    @Test
    func `analyzing no side clears every finding at once`() async throws {
        let sut = try makeSUT(mode: .both, findings: [Self.rightRoot: [Self.finding(line: 2)]])
        sut.model.comparisonChanged(.init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)))
        try await finish(sut)

        sut.settings.analyzedSides = .none

        #expect(sut.model.findingsByFile.isEmpty)
        #expect(sut.model.summary.isEmpty)
    }

    @Test
    func `dropping the left side keeps the right side's findings`() async throws {
        let sut = try makeSUT(
            mode: .both,
            findings: [Self.leftRoot: [Self.finding(line: 1)], Self.rightRoot: [Self.finding(line: 2)]])
        sut.model.comparisonChanged(.init(left: Self.folder(Self.leftRoot), right: Self.folder(Self.rightRoot)))
        try await finish(sut)

        sut.settings.analyzedSides = .rightOnly

        #expect(sut.model.leftFindingsByFile.isEmpty)
        #expect(sut.model.findingsByFile["A.swift"]?.map(\.line) == [2])
        try await finish(sut)
    }

    @Test
    func `each side offers the analyzers its own changed Swift files, by its own paths`() async throws {
        let harness = ModelTestHarness()
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("A.swift", "1"), harness.entry("notes.txt", "1")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("A.swift", "2"), harness.entry("notes.txt", "2")
        ]
        try await harness.load(sut)
        sut.settings.diagnosticsEnabled = true
        sut.settings.analyzedSides = .both
        sut.settings.toolLocations = Self.tools
        let runner = SideRecordingRunner(findingsByRoot: [:])
        let clock = TestClock()
        sut.diagnostics = DiagnosticsModel(
            engine: runner, settings: sut.settings, taskProvider: harness.taskProvider, clock: clock,
            debounce: Self.debounce)

        sut.updateAnalyzedSides()
        try await clock.waitForSleepers()
        clock.advance(by: Self.debounce)
        try await harness.taskProvider.waitForAllTasks()

        let files = Dictionary(uniqueKeysWithValues: await runner.requests.map { ($0.root, $0.files) })
        #expect(
            files[ModelTestHarness.leftURL] == [
                .init(path: "A.swift", contentHash: "1", url: ModelTestHarness.leftURL.appending(path: "A.swift"))
            ])
        #expect(
            files[ModelTestHarness.rightURL] == [
                .init(path: "A.swift", contentHash: "2", url: ModelTestHarness.rightURL.appending(path: "A.swift"))
            ])
    }

    @Test
    func `a changeset without a Swift file runs no tool`() async throws {
        let sut = try makeSUT(mode: .rightOnly)

        sut.model.comparisonChanged(root: Self.rightRoot, files: [], corpusFingerprint: "fp")
        try await sut.spy.waitForAllTasks()

        #expect(await sut.runner.requests.isEmpty)
        #expect(!sut.model.isRunning)
    }
}

/// A directory the tests make a trust decision about, since trust is kept per existing, canonical root.
@MainActor
private struct TrustedRepository {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "GitDiffViewerTests.trust.\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func trust(in store: RepositoryTrust) {
        store.requestTrust(for: root)
        guard let request = store.claimNextRequest() else { return }
        store.answer(request, trusts: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Records every request it runs and answers SwiftLint's with the findings configured for the request's root.
private actor SideRecordingRunner: DiagnosticsRunning {
    private let findingsByRoot: [URL: [Finding]]
    private(set) var requests: [DiagnosticsEngine.Request] = []

    init(findingsByRoot: [URL: [Finding]]) {
        self.findingsByRoot = findingsByRoot
    }

    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        requests.append(request)
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: findingsByRoot[request.root] ?? [], status: .succeeded, duration: .zero,
            fromCache: false)
    }
}

/// Names each ref's tree after the ref and "exports" it to one fixed folder, counting how often.
private final class RecordingExporter: DiagnosticsTreeExporting {
    static let folder = URL(filePath: "/exported", directoryHint: .isDirectory)
    private let count = Mutex(0)

    var materializations: Int { count.withLock { $0 } }

    func treeID(of ref: String, in repository: URL) async throws -> String {
        "tree-\(ref)"
    }

    func materializer(for tree: String, in repository: URL) -> DiagnosticsMaterializer {
        { [self] body in
            count.withLock { $0 += 1 }
            try await body(Self.folder)
        }
    }
}
