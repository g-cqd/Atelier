import AemiCore
import AemiTesting
import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// How ``DiffViewerModel`` feeds ``DiffTextKit/DiagnosticOverlay``'s mapper and a card's badge: the fileIndex→path
/// map behind the current render target, and a file's own severity counts.
@MainActor
struct DiffViewerModelDiagnosticsTests {
    private let harness = ModelTestHarness()

    private func finding(file: String, severity: Finding.Severity = .warning) -> Finding {
        Finding(tool: .swiftlint, ruleID: "rule", message: "message", file: file, line: 1, severity: severity)
    }

    @Test
    func `diagnosticFilePaths maps the selected file's fileIndex to its right path`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)

        sut.select("a.swift")

        #expect(sut.diagnosticFilePaths == [0: "a.swift"])
    }

    @Test
    func `diagnosticFilePaths follows the render target from the card list to one of its files`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "1")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "2"), harness.entry("b.swift", "2")
        ]
        try await harness.load(sut)
        try #require(sut.diagnosticFilePaths == [0: "a.swift", 1: "b.swift"])

        sut.select("b.swift")

        #expect(sut.diagnosticFilePaths == [0: "b.swift"])
        #expect(sut.diagnosticLeftFilePaths == [0: "b.swift"])
    }

    @Test
    func `diagnosticFilePaths is empty with nothing rendered`() {
        let sut = harness.makeSUT()

        #expect(sut.diagnosticFilePaths.isEmpty)
    }

    @Test
    func `diagnosticSeverityCounts reads a file's findings under its right path`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("Old.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("New.swift", "2")]
        harness.reader.gitRenames = ["Old.swift": "New.swift"]
        try await harness.load(sut)

        let diagnosticsModel = DiagnosticsModel(
            engine: StubDiagnosticsRunner(), settings: sut.settings, taskProvider: harness.taskProvider)
        sut.diagnostics = diagnosticsModel

        #expect(sut.diagnosticSeverityCounts(for: "Old.swift").isEmpty)
    }

    @Test
    func `diagnosticSeverityCounts is empty with no diagnostics model attached`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)

        #expect(sut.diagnosticSeverityCounts(for: "a.swift").isEmpty)
    }
}

/// A ``DiagnosticsRunning`` that never finds anything, so these tests only exercise the wiring, not a real run.
private actor StubDiagnosticsRunner: DiagnosticsRunning {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        DiagnosticsEngine.ToolResult(tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
    }
}
