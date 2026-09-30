import AemiTesting
import AppKit
import AtelierDiagnostics
import Foundation
import QuartzCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import GitDiffViewer

/// The comparison window's toolbar holds the same items whatever the window shows (book WIN-02). Every comparison
/// window shares one toolbar identifier, so AppKit mirrors an item inserted in one window into all the others; an
/// item that one window has and another lacks makes that mirrored insert throw, and the app crashes. An item whose
/// content has nothing to show must therefore keep its place instead of leaving the toolbar.
@MainActor
@Suite(.mainActorLane)
struct ToolbarItemSetTests {
    private let harness = ModelTestHarness()

    @Test
    func `findings arriving or diagnostics switching off leave the toolbar's items as they were`() async throws {
        let model = harness.makeSUT()
        let window = Self.window(showing: model)
        defer { window.close() }
        Self.draw(window)
        let quiet = try Self.items(of: window)

        let spy = TaskProviderSpy.tolerant()
        model.settings.diagnosticsEnabled = true
        let diagnostics = DiagnosticsModel(
            engine: OneWarningRunner(), settings: model.settings, taskProvider: spy, debounce: .milliseconds(1))
        model.diagnostics = diagnostics
        diagnostics.comparisonChanged(
            root: URL(filePath: "/repo"), files: [.init(path: "A.swift", contentHash: "a", url: nil)],
            corpusFingerprint: "fp")
        try await spy.waitForAllTasks()
        try #require(!diagnostics.summary.isEmpty)
        Self.draw(window)
        let withFindings = try Self.items(of: window)
        #expect(withFindings == quiet)

        model.settings.diagnosticsEnabled = false
        try await spy.waitForAllTasks()
        Self.draw(window)
        let switchedOff = try Self.items(of: window)
        #expect(switchedOff == quiet)
    }

    /// The items a toolbar shows, in order, and every item its delegate can make.
    private struct Items: Equatable {
        let shown: [String]
        let allowed: Set<String>
    }

    private static func items(of window: NSWindow) throws -> Items {
        let toolbar = try #require(window.toolbar)
        let allowed = toolbar.delegate?.toolbarAllowedItemIdentifiers?(toolbar) ?? []
        return Items(
            shown: toolbar.items.map(\.itemIdentifier.rawValue), allowed: Set(allowed.map(\.rawValue)))
    }

    /// The window's content with its toolbar bridged onto the window, which is never ordered in. The toolbar keeps
    /// no saved arrangement, so the test neither reads nor writes one.
    private static func window(showing model: DiffViewerModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: ContentView(settings: model.settings, model: model))
        controller.sceneBridgingOptions = [.toolbars]
        window.contentViewController = controller
        return window
    }

    private static func draw(_ window: NSWindow) {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.toolbar?.autosavesConfiguration = false
        window.displayIfNeeded()
        CATransaction.flush()
    }
}

/// Finds one warning in the first changed file, whichever tool runs.
private struct OneWarningRunner: DiagnosticsRunning {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        let finding = Finding(
            tool: tool, ruleID: "rule", message: "message", file: "A.swift", line: 1, severity: .warning)
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: [finding], status: .succeeded, duration: .zero, fromCache: false)
    }
}
