import AemiTesting
import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A Findings row opens its file and scrolls to its line (DUI-01, GDV S18): which row shows the line, and the model's
/// hand-over of that row once the file is on screen.
@MainActor
@Suite(.mainActorLane)
struct FindingRevealTests {
    private let harness = ModelTestHarness()
    private let old = "one\ntwo\nthree\nfour\n"
    private let new = "one\nTWO\nthree\nfour\nfive\n"

    @Test
    func `the reveal row of the split layout shows the finding's new line`() throws {
        let rendered = DiffRenderer.render(oldText: old, newText: new, language: .plain)

        let row = try #require(FindingReveal(leftPath: "a.swift", line: 5).row(in: rendered, inline: false))

        #expect(rendered.new?.rows[row].newNumber == 5)
    }

    @Test
    func `the reveal row of the inline layout shows the finding's new line`() throws {
        let rendered = DiffRenderer.render(oldText: old, newText: new, language: .plain)

        let row = try #require(FindingReveal(leftPath: "a.swift", line: 2).row(in: rendered, inline: true))

        #expect(rendered.unified?.rows[row].newNumber == 2)
    }

    @Test
    func `a left-side finding reveals the row showing its old line`() throws {
        let rendered = DiffRenderer.render(oldText: old, newText: new, language: .plain)

        let row = try #require(
            FindingReveal(leftPath: "a.swift", line: 2, side: .left).row(in: rendered, inline: false))

        #expect(rendered.old?.rows[row].oldNumber == 2)
    }

    @Test
    func `a line hidden in a gap reveals the last row shown before it`() throws {
        let long = (1 ... 30).map { "line \($0)\n" }.joined()
        let changed = long.replacingOccurrences(of: "line 5\n", with: "line five\n")
            .replacingOccurrences(of: "line 30\n", with: "line thirty\n")
        let rendered = DiffRenderer.render(
            oldText: long, newText: changed, language: .plain, layout: .changes(context: 1, expansions: [:]))

        let row = try #require(FindingReveal(leftPath: "a.swift", line: 12).row(in: rendered, inline: false))

        #expect(rendered.new?.rows[row].newNumber == 6)
    }

    @Test
    func `a line hidden before every shown line reveals the first row`() throws {
        let long = (1 ... 30).map { "line \($0)\n" }.joined()
        let changed = long.replacingOccurrences(of: "line 30\n", with: "line thirty\n")
        let rendered = DiffRenderer.render(
            oldText: long, newText: changed, language: .plain, layout: .changes(context: 1, expansions: [:]))

        let row = try #require(FindingReveal(leftPath: "a.swift", line: 12).row(in: rendered, inline: false))

        #expect(row == 0)
        #expect(rendered.new?.rows[row].newNumber == 29)
    }

    @Test
    func `a Findings row scrolls the window to its finding's line once the file is rendered`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.diagnostics = DiagnosticsModel(
            engine: SilentDiagnosticsRunner(), settings: sut.settings, taskProvider: harness.taskProvider)
        let finding = Finding(
            tool: .swiftlint, ruleID: "rule", message: "message", file: "a.swift", line: 1, severity: .warning)

        sut.reveal(finding)
        try await harness.taskProvider.waitForAllTasks()

        let row = try #require(sut.scrollRequest?.row)
        #expect(sut.selectedPath == "a.swift")
        #expect(sut.rendered?.new?.rows[row].newNumber == 1)
        #expect(sut.takeFindingReveal() == nil)
    }
}

/// A ``DiagnosticsRunning`` that never finds anything.
private actor SilentDiagnosticsRunner: DiagnosticsRunning {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        DiagnosticsEngine.ToolResult(tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
    }
}
