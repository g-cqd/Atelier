import AemiTesting
import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
import Foundation
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffTextKit
@testable import GitDiffViewer

/// Each card pane of the card list, the default view, shows its own file's findings on their rows (book DIAG-03): the
/// card's rows carry the comparison's file indexes, so a file's findings never land on another card, and a finding on
/// a line a gap hides lands on no row.
@MainActor
struct CardListDiagnosticsTests {
    private let harness = ModelTestHarness()
    private static let debounce: Duration = .milliseconds(250)
    /// Every tool named, SwiftLint alone enabled.
    private static let onlySwiftLint = Dictionary(
        uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation(isEnabled: $0 == .swiftlint)) })

    private static func finding(_ file: String, line: Int, rule: String) -> Finding {
        Finding(
            tool: .swiftlint, ruleID: rule, message: "message", file: file, line: line, column: 1, severity: .warning)
    }

    /// Three files of thirty lines, each changed at line 20 alone, so a card shows lines 17 to 23 and hides the rest.
    private func serveThreeFiles() {
        let lines = (1 ... 30).map { "let line\($0) = \($0)" }
        var changed = lines
        changed[19] = "let line20 = 2_000"
        harness.reader.blobContents["1"] = lines.joined(separator: "\n") + "\n"
        harness.reader.blobContents["2"] = changed.joined(separator: "\n") + "\n"
        for side in [ModelTestHarness.leftURL: "1", ModelTestHarness.rightURL: "2"] {
            harness.reader.entries[.directory(side.key)] = ["a.swift", "b.swift", "c.swift"]
                .map { harness.entry($0, side.value) }
        }
    }

    @Test
    func `each card pane shows its own file's findings on the rows of their lines`() async throws {
        serveThreeFiles()
        let sut = harness.makeSUT()
        try await harness.load(sut)
        try await analyze(
            sut,
            findings: [
                Self.finding("a.swift", line: 20, rule: "a20"), Self.finding("b.swift", line: 18, rule: "b18"),
                Self.finding("b.swift", line: 20, rule: "b20"),
                // Hidden in the gap above the change.
                Self.finding("b.swift", line: 2, rule: "b2")
            ])
        let list = CardList(model: sut)
        defer { list.close() }
        list.pump()
        try await harness.taskProvider.waitForAllTasks()
        list.pump()

        let paths = sut.renderedFiles.map(\.path)
        let cards = list.cards()
        try #require(cards.count == 3)
        var shown: [String: Set<String>] = [:]
        for (path, card) in zip(paths, cards) { shown[path] = CardList.findings(in: card) }
        #expect(shown["a.swift"] == ["20 a20"])
        #expect(shown["b.swift"] == ["18 b18", "20 b20"])
        #expect(shown["c.swift"] == [])
    }

    /// Turns diagnostics on with `findings` as SwiftLint's answer on the right side, and lets the run land.
    private func analyze(_ sut: DiffViewerModel, findings: [Finding]) async throws {
        sut.settings.diagnosticsEnabled = true
        sut.settings.analyzedSides = .rightOnly
        sut.settings.toolLocations = Self.onlySwiftLint
        let clock = TestClock()
        sut.diagnostics = DiagnosticsModel(
            engine: FixedFindingsRunner(findings: findings), settings: sut.settings,
            taskProvider: harness.taskProvider, clock: clock, debounce: Self.debounce)
        let mark = clock.registrationMark()
        sut.updateAnalyzedSides()
        try await clock.expectSleepers(after: mark)
        clock.advance(by: Self.debounce)
        try await harness.taskProvider.waitForAllTasks()
        try #require(sut.diagnostics?.findingsByFile.values.joined().count == findings.count)
    }
}

/// The card list of a model, in a window that is never ordered in.
@MainActor
private final class CardList {
    private let window: NSWindow

    init(model: DiffViewerModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CombinedDiffView(model: model))
    }

    func close() {
        window.close()
    }

    /// One turn of the run loop, then a layout pass of the whole list; twice, since cards measure once they have a
    /// width.
    func pump() {
        for _ in 0 ..< 2 {
            RunLoop.main.run(mode: .default, before: .distantPast)
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// The list's cards, from top to bottom.
    func cards() -> [StickyCardView] {
        Self.all(StickyCardView.self, in: window.contentView)
            // Window coordinates grow upward.
            .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }

    /// Every finding `card`'s panes show, as its row's new line number and its rule.
    static func findings(in card: StickyCardView) -> Set<String> {
        var shown: Set<String> = []
        for gutter in all(DiffGutterView.self, in: card) {
            guard let rendered = gutter.rendered else { continue }
            for (row, diagnostics) in gutter.overlay?.snapshot() ?? [:] {
                let line = rendered.rows[row].newNumber.map(String.init) ?? "-"
                for finding in diagnostics.findings { shown.insert("\(line) \(finding.ruleID)") }
            }
        }
        return shown
    }

    private static func all<View: NSView>(_ type: View.Type, in root: NSView?) -> [View] {
        var found: [View] = []
        var pending: [NSView] = root.map { [$0] } ?? []
        while let view = pending.popLast() {
            if let match = view as? View { found.append(match) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }
}

/// Answers every SwiftLint run with the same findings.
private actor FixedFindingsRunner: DiagnosticsRunning {
    let findings: [Finding]

    init(findings: [Finding]) {
        self.findings = findings
    }

    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        DiagnosticsEngine.ToolResult(
            tool: tool, findings: findings, status: .succeeded, duration: .zero, fromCache: false)
    }
}
