import AemiTesting
import AppKit
import AtelierSources
import Foundation
import QuartzCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffRendering
@testable import DiffTextKit
@testable import GitDiffViewer

/// The scrolling settings in the detail area as the window shows it, its tabs, file panes and card list included
/// (book SET-09): each reaches the panes on screen at once, and with the scroll to the first change off, files open
/// at their top while a tab shown again still comes back where it was (DIFF-08). The panes are read as
/// `FileTabScrollRangeTests` reads them.
@MainActor
struct ScrollingSettingsPaneTests {
    private let harness = ModelTestHarness()

    /// A file opens at its top, one that fits shows whole, and a tab shown again after the file list comes back where
    /// its pane was (book DIFF-08, criteria 2 to 4).
    @Test
    func `with the scroll to the first change off, files open at their top and tabs come back where they were`()
        async throws
    {
        let model = try await showing(short: true)
        model.settings.scrollsToFirstChange = false
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)

        model.pin("long.swift")
        try await settle(window)
        try Self.expectTop(of: model, in: content, "a long file")
        for pane in try FileTabScrollRangeTests.panes(in: content) { FileTabScrollRangeTests.scroll(pane, to: 555) }
        try await settle(window)
        let before = try FileTabScrollRangeTests.panes(in: content).map { try FileTabScrollRangeTests.topRow(of: $0) }

        model.showFileList()
        try await settle(window)
        model.activateTab(try #require(model.tabs.active?.id ?? model.tabs.tabs.first?.id))
        try await settle(window)
        let after = try FileTabScrollRangeTests.panes(in: content).map { try FileTabScrollRangeTests.topRow(of: $0) }
        #expect(after.map(\.row) == before.map(\.row))
        for (was, now) in zip(before, after) { #expect(abs(was.offset - now.offset) < 1) }

        model.select("short.swift")
        try await settle(window)
        try Self.expectTop(of: model, in: content, "a file that fits")
        try FileTabScrollRangeTests.expectWhole(in: content, "a file that fits")
    }

    /// Bouncing at the edges and scrolling past the last line, each turned on then off again, reach an open file's
    /// panes.
    @Test
    func `the scrolling settings reach the open file panes at once`() async throws {
        let model = try await showing(short: false)
        // Open before the window is made, which then never lays out the file list's card: only the pane is read.
        model.pin("long.swift")
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await settle(window)

        for bounces in [true, false] {
            model.settings.bouncesAtEdges = bounces
            try await settle(window)
            let elasticity: NSScrollView.Elasticity = bounces ? .automatic : .none
            for pane in try FileTabScrollRangeTests.panes(in: content) {
                let scrollView = try #require(pane.clip.enclosingScrollView)
                #expect(scrollView.verticalScrollElasticity == elasticity, "bouncing \(bounces)")
                #expect(scrollView.horizontalScrollElasticity == elasticity, "bouncing \(bounces)")
            }
        }
        for pastEnd in [true, false] {
            model.settings.scrollsPastEnd = pastEnd
            try await settle(window)
            for pane in try FileTabScrollRangeTests.panes(in: content) {
                // Its lines are short and never wrap: its rows at one line each are its text's height.
                let end =
                    pastEnd
                    ? pane.rowsHeight - pane.below - pane.lineHeight + pane.clip.bounds.height : pane.rowsHeight
                #expect(abs(pane.textView.frame.height - end) < 1, "scrolling past the end \(pastEnd)")
            }
        }
    }

    /// Bouncing reaches the cards' panes, which rubber-band sideways, and leaves the card list's own bounce as it is,
    /// on or off (D25).
    @Test
    func `bouncing reaches the cards' panes and leaves the card list's own bounce as it is`() async throws {
        // The short file's card alone: a 200-line card laid out again on each change of setting says nothing more.
        let model = try await showing(long: false, short: true)
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await settle(window)
        #expect(model.detailState == .cards)
        let list = try #require(subviews(of: StickyCardView.self, in: content).first?.enclosingScrollView)
        let listElasticity = (list.verticalScrollElasticity, list.horizontalScrollElasticity)

        for bounces in [true, false] {
            model.settings.bouncesAtEdges = bounces
            try await settle(window)
            #expect(list.verticalScrollElasticity == listElasticity.0, "bouncing \(bounces)")
            #expect(list.horizontalScrollElasticity == listElasticity.1, "bouncing \(bounces)")
            let panes = subviews(of: DiffPaneTextView.self, in: content).compactMap(\.enclosingScrollView)
            try #require(!panes.isEmpty)
            for pane in panes {
                #expect(pane.horizontalScrollElasticity == (bounces ? .automatic : .none), "bouncing \(bounces)")
                #expect(pane.verticalScrollElasticity == .none, "bouncing \(bounces)")
            }
        }
    }

    /// A model over `long.swift`, 200 lines changed at the 121st, unless not `long`, and, when `short`, `short.swift`,
    /// which fits a pane, shown inline, its comparison loaded.
    private func showing(long includesLong: Bool = true, short: Bool) async throws -> DiffViewerModel {
        let long = (1 ... 200).map { "let value\($0) = \($0)" }
        let shortLines = (1 ... 10).map { "let value\($0) = \($0)" }
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] =
            (includesLong ? [harness.entry("long.swift", "3")] : [])
            + (short ? [harness.entry("short.swift", "1")] : [])
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] =
            (includesLong ? [harness.entry("long.swift", "4")] : [])
            + (short ? [harness.entry("short.swift", "2")] : [])
        harness.reader.blobContents["1"] = FileTabScrollRangeTests.text(shortLines)
        harness.reader.blobContents["2"] = FileTabScrollRangeTests.text(shortLines, changing: 9)
        harness.reader.blobContents["3"] = FileTabScrollRangeTests.text(long)
        harness.reader.blobContents["4"] = FileTabScrollRangeTests.text(long, changing: 120)
        let model = harness.makeSUT()
        model.settings.mode = .inline
        try await harness.load(model)
        return model
    }

    /// The model asks for no row, and each file pane shows its text from its top, its text view covering it.
    private static func expectTop(of model: DiffViewerModel, in content: NSView, _ comment: Comment) throws {
        #expect(model.scrollRequest == nil, comment)
        for pane in try FileTabScrollRangeTests.panes(in: content) {
            #expect(pane.clip.bounds.minY == 0, comment)
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
        }
    }

    /// The detail area, as the window hosts it, in a window that is never ordered in.
    private static func window(showing model: DiffViewerModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DiffDetailView(model: model))
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
