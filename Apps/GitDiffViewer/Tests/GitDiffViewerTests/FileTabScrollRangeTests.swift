import AemiTesting
import AppKit
import AtelierSources
import Foundation
import QuartzCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffTextKit
@testable import GitDiffViewer

/// A file opened from the list, by a click into the temporary tab or by a double click into a pinned one, scrolls in
/// the window's whole content, with the explorers above the detail area or in the sidebar, inline or side by side: each
/// of its panes ends past its viewport by what puts its last line at the top. The file is shorter than the pane in either placement, which is
/// what left a pane with nothing to scroll (`FilePaneScrollRangeTests`).
@MainActor
struct FileTabScrollRangeTests {
    private let harness = ModelTestHarness()

    @Test(arguments: [ExplorerPlacement.top, .sidebar], [ViewMode.inline, .split])
    func `a short file opened from the list scrolls, in the temporary tab and in a pinned one`(
        placement: ExplorerPlacement, mode: ViewMode
    ) async throws {
        let lines = (1 ... 10).map { "let value\($0) = \($0)" }
        var changed = lines
        changed[4] = "let changed = true"
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.reader.blobContents["1"] = lines.joined(separator: "\n") + "\n"
        harness.reader.blobContents["2"] = changed.joined(separator: "\n") + "\n"
        let model = harness.makeSUT()
        model.settings.explorerPlacement = placement
        model.settings.mode = mode
        let panes = mode == .inline ? 1 : 2
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await harness.load(model)
        try await settle(window)
        #expect(model.detailState == .cards)

        model.select("a.swift")
        try await settle(window)
        try expectEachFilePaneScrollsToItsLastLine(in: content, count: panes, "opened by a click")

        model.closeTab(try #require(model.tabs.active).id)
        try await settle(window)
        model.pin("a.swift")
        try await settle(window)
        try expectEachFilePaneScrollsToItsLastLine(in: content, count: panes, "opened by a double click")
    }

    /// The window's content, toolbar and explorers included, as the app makes it, in a window that is never ordered in.
    private static func window(showing model: DiffViewerModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(settings: model.settings, model: model))
        return window
    }

    /// Lets every task the model spawned end, then lays out and draws the window, with one turn of the run loop.
    private func settle(_ window: NSWindow) async throws {
        try await harness.taskProvider.waitForAllTasks()
        Self.draw(window)
    }

    private static func draw(_ window: NSWindow) {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }
}
