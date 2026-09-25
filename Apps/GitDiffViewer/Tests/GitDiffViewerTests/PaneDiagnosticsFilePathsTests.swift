import AemiTesting
import AtelierDiagnostics
import DiffCore
import DiffRendering
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import GitDiffViewer

/// Every card pane maps the model's findings to its rows through the comparison's file-index-to-path maps, on every
/// findings change: the model builds those maps once per render target, not once per pane, so a change costs the card
/// list its card count rather than its square.
@MainActor
@Suite(.mainActorLane)
struct PaneDiagnosticsFilePathsTests {
    private let harness = ModelTestHarness()

    @Test
    func `the card panes share one build of the path maps across findings changes`() async throws {
        let paths = (0 ..< 12).map { "file\($0).swift" }
        for side in [ModelTestHarness.leftURL: "1", ModelTestHarness.rightURL: "2"] {
            harness.reader.entries[.directory(side.key)] = paths.map { harness.entry($0, side.value) }
        }
        let sut = harness.makeSUT()
        try await harness.load(sut)
        sut.settings.diagnosticsEnabled = true
        sut.diagnostics = DiagnosticsModel(
            engine: SilentDiagnosticsRunner(), settings: sut.settings, taskProvider: harness.taskProvider)
        let texts = sut.renderedFiles.compactMap { $0.rendered.unified ?? $0.rendered.new }
        try #require(texts.count == paths.count)
        let panes = texts.map { _ in PaneDiagnostics() }

        // Two findings changes, each recomputing every pane as `followingDiagnostics` does.
        for _ in 0 ..< 2 {
            for (pane, text) in zip(panes, texts) { pane.recompute(for: text, model: sut) }
            try await harness.taskProvider.waitForAllTasks()
        }

        #expect(sut.diagnosticFilePathBuilds == 1)
    }
}

/// A ``DiagnosticsRunning`` that never finds anything: these tests read the path maps, not a run's findings.
private actor SilentDiagnosticsRunner: DiagnosticsRunning {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        DiagnosticsEngine.ToolResult(tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
    }
}
