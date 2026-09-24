import AemiTesting
import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import GitDiffViewer

/// The time to appearance ends when the detail area's panes first show the file, whichever layout shows it: the
/// panes are new when the file opens, so their creation, not only a later update, reports it.
@MainActor
struct FileAppearanceTimingTests {
    private let harness = ModelTestHarness()

    @Test(arguments: [ViewMode.inline])
    func `a file opened in new panes is timed to their appearance`(mode: ViewMode) async throws {
        let sut = harness.makeSUT()
        sut.settings.mode = mode
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.select("a.swift")
        sut.settings.granularity = .character
        harness.uptime.now = .milliseconds(200)
        sut.renderSelection()
        harness.uptime.now = .milliseconds(230)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.timing == RenderTiming(firstDisplay: nil, rendered: .milliseconds(30)))

        harness.uptime.now = .milliseconds(245)
        let window = Self.offscreenWindow(showing: DiffDetailView(model: sut))
        defer { window.close() }
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: .milliseconds(45), rendered: .milliseconds(30)))
    }

    /// A window never ordered in, its content laid out once.
    private static func offscreenWindow(showing view: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }
}
