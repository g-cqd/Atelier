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

/// A file opened from the list, by a click into the temporary tab or by a double click into a pinned one, in the
/// window's whole content, with the explorers above the detail area or in the sidebar, inline or side by side: a file
/// that fits its pane shows whole from its top, and a longer one opens with its first change three lines below the
/// pane's top (book DIFF-08), or at its top when that scroll is turned off. Either way each pane's text view covers
/// its text: a pane sized while TextKit had laid nothing out ended above its text and did not scroll
/// (`FilePaneScrollRangeTests`). The scrolling settings reach the panes on screen at once (book SET-09).
@MainActor
struct FileTabScrollRangeTests {
    private let harness = ModelTestHarness()

    /// One window, as the app keeps one while its explorers move and its layout changes, which a window each would
    /// cost four times over.
    @Test(arguments: [true, false])
    func `a file opened from the list shows whole when it fits, else from its first change if that scroll is on`(
        scrollsToFirstChange: Bool
    ) async throws {
        let short = (1 ... 10).map { "let value\($0) = \($0)" }
        let long = (1 ... 200).map { "let value\($0) = \($0)" }
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("long.swift", "3"), harness.entry("short.swift", "1")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("long.swift", "4"), harness.entry("short.swift", "2")
        ]
        harness.reader.blobContents["1"] = Self.text(short)
        harness.reader.blobContents["2"] = Self.text(short, changing: 9)
        harness.reader.blobContents["3"] = Self.text(long)
        harness.reader.blobContents["4"] = Self.text(long, changing: 120)
        let model = harness.makeSUT()
        model.settings.scrollsToFirstChange = scrollsToFirstChange
        model.settings.explorerPlacement = .sidebar
        model.settings.mode = .inline
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await harness.load(model)
        try await settle(window)
        #expect(model.detailState == .cards)

        model.select("short.swift")
        try await settle(window)
        try Self.expectWhole(in: content, "explorers in the sidebar, inline, opened by a click")

        model.settings.mode = .split
        model.pin("long.swift")
        try await settle(window)
        try Self.expectOpened(
            of: model, in: content, scrollsToFirstChange: scrollsToFirstChange,
            "explorers in the sidebar, side by side, opened by a double click")

        model.settings.explorerPlacement = .top
        model.closeTab(try #require(model.tabs.active).id)
        try await settle(window)
        model.closeTab(try #require(model.tabs.active).id)
        try await settle(window)
        model.pin("short.swift")
        try await settle(window)
        try Self.expectWhole(in: content, "explorers above, side by side, opened by a double click")

        model.settings.mode = .inline
        model.select("long.swift")
        try await settle(window)
        try Self.expectOpened(
            of: model, in: content, scrollsToFirstChange: scrollsToFirstChange,
            "explorers above, inline, opened by a click")
    }

    /// A tab shown again after the file list comes back where its panes were, not to its first change nor to its top,
    /// whether files open on their first change or not (book TAB-10, DIFF-08): side by side with the explorers in the
    /// sidebar, then inline with them above.
    @Test(arguments: [true, false])
    func `a file tab shown again comes back where it was scrolled, whether files open on their first change or not`(
        scrollsToFirstChange: Bool
    ) async throws {
        let long = (1 ... 200).map { "let value\($0) = \($0)" }
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("long.swift", "3")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("long.swift", "4")]
        harness.reader.blobContents["3"] = Self.text(long)
        harness.reader.blobContents["4"] = Self.text(long, changing: 120)
        let model = harness.makeSUT()
        model.settings.scrollsToFirstChange = scrollsToFirstChange
        model.settings.explorerPlacement = .sidebar
        model.settings.mode = .split
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await harness.load(model)
        try await settle(window)

        for (placement, mode) in [(ExplorerPlacement.sidebar, ViewMode.split), (.top, .inline)] {
            let comment: Comment = "explorers \(placement.rawValue), \(mode.rawValue)"
            model.settings.explorerPlacement = placement
            model.settings.mode = mode
            model.pin("long.swift")
            try await settle(window)
            try Self.expectOpened(of: model, in: content, scrollsToFirstChange: scrollsToFirstChange, comment)
            for pane in try Self.panes(in: content) { Self.scroll(pane, to: 555) }
            try await settle(window)
            let before = try Self.panes(in: content).map { try Self.topRow(of: $0) }

            model.showFileList()
            try await settle(window)
            model.activateTab(try #require(model.tabs.active?.id ?? model.tabs.tabs.first?.id))
            try await settle(window)

            #expect(model.scrollRequest == nil, comment)
            let after = try Self.panes(in: content).map { try Self.topRow(of: $0) }
            #expect(after.map(\.row) == before.map(\.row), comment)
            for (was, now) in zip(before, after) { #expect(abs(was.offset - now.offset) < 1, comment) }
            model.closeTab(try #require(model.tabs.active).id)
            try await settle(window)
        }
    }

    /// Bouncing at the edges and scrolling past the last line, each turned on then off again in the window's
    /// settings, reach the file panes on screen (book SET-09).
    @Test
    func `the scrolling settings reach the open file panes at once`() async throws {
        let long = (1 ... 200).map { "let value\($0) = \($0)" }
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("long.swift", "3")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("long.swift", "4")]
        harness.reader.blobContents["3"] = Self.text(long)
        harness.reader.blobContents["4"] = Self.text(long, changing: 120)
        let model = harness.makeSUT()
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await harness.load(model)
        model.pin("long.swift")
        try await settle(window)

        for bounces in [true, false] {
            model.settings.bouncesAtEdges = bounces
            try await settle(window)
            let elasticity: NSScrollView.Elasticity = bounces ? .automatic : .none
            for pane in try Self.panes(in: content) {
                let scrollView = try #require(pane.clip.enclosingScrollView)
                #expect(scrollView.verticalScrollElasticity == elasticity, "bouncing \(bounces)")
                #expect(scrollView.horizontalScrollElasticity == elasticity, "bouncing \(bounces)")
            }
        }
        for pastEnd in [true, false] {
            model.settings.scrollsPastEnd = pastEnd
            try await settle(window)
            for pane in try Self.panes(in: content) {
                // Its lines are short and never wrap: its rows at one line each are its text's height.
                let end =
                    pastEnd
                    ? pane.rowsHeight - pane.below - pane.lineHeight + pane.clip.bounds.height : pane.rowsHeight
                #expect(abs(pane.textView.frame.height - end) < 1, "scrolling past the end \(pastEnd)")
            }
        }
    }

    /// Bouncing reaches the panes of the cards on screen, which rubber-band sideways, and leaves the card list's own
    /// bounce as it is, on or off (book SET-09, D25).
    @Test
    func `bouncing reaches the cards' panes and leaves the card list's own bounce as it is`() async throws {
        let short = (1 ... 10).map { "let value\($0) = \($0)" }
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("short.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("short.swift", "2")]
        harness.reader.blobContents["1"] = Self.text(short)
        harness.reader.blobContents["2"] = Self.text(short, changing: 5)
        let model = harness.makeSUT()
        let window = Self.window(showing: model)
        defer { window.close() }
        let content = try #require(window.contentView)
        try await harness.load(model)
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

    private static func scroll(_ pane: ShownPane, to y: CGFloat) {
        pane.clip.scroll(to: NSPoint(x: 0, y: y))
        pane.clip.enclosingScrollView?.reflectScrolledClipView(pane.clip)
    }

    /// The row at the top of `pane`, and how far into its line the pane is scrolled.
    private static func topRow(of pane: ShownPane) throws -> (row: Int, offset: CGFloat) {
        let layoutManager = try #require(pane.textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let origin = pane.textView.textContainerOrigin.y
        let fragment = try #require(
            layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: pane.clip.bounds.minY - origin)))
        let row = pane.rendered.rowIndex(
            containing: content.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        )
        return (row, pane.clip.bounds.minY - origin - fragment.layoutFragmentFrame.minY)
    }

    private static func text(_ lines: [String], changing changed: Int? = nil) -> String {
        var lines = lines
        if let changed { lines[changed] = "let changed = true" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Each file pane shows the row the model asked for three lines below its top, and covers its text.
    private static func expectFirstChange(of model: DiffViewerModel, in content: NSView, _ comment: Comment) throws {
        let row = try #require(model.scrollRequest?.row, comment)
        for pane in try panes(in: content) {
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
            let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
            #expect(abs(below - 3 * pane.lineHeight) < 1, "\(comment): the row is \(below) below the pane's top")
        }
    }

    /// Each file pane shows the row the model asked for three lines below its top when files open on their first
    /// change; otherwise the model asks for none and each pane shows its text from its top.
    private static func expectOpened(
        of model: DiffViewerModel, in content: NSView, scrollsToFirstChange: Bool, _ comment: Comment
    ) throws {
        guard !scrollsToFirstChange else { return try expectFirstChange(of: model, in: content, comment) }
        #expect(model.scrollRequest == nil, comment)
        for pane in try panes(in: content) {
            #expect(pane.clip.bounds.minY == 0, comment)
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
        }
    }

    /// Each file pane shows its text whole, from its top, its text view filling the pane.
    private static func expectWhole(in content: NSView, _ comment: Comment) throws {
        for pane in try panes(in: content) {
            #expect(pane.clip.bounds.minY == 0, comment)
            #expect(pane.textView.frame.height >= pane.clip.bounds.height, comment)
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
            #expect(try pane.bottom(ofRow: pane.lastRow) + pane.below <= pane.clip.bounds.height, comment)
        }
    }

    /// The file panes: the text views that scroll, which a card's do not.
    private static func panes(in content: NSView) throws -> [ShownPane] {
        let textViews = subviews(of: DiffPaneTextView.self, in: content).filter { $0.enclosingScrollView != nil }
        try #require(!textViews.isEmpty)
        return try textViews.map { textView in
            let gutter = try #require(subviews(of: DiffGutterView.self, in: content).first { $0.source === textView })
            return ShownPane(
                textView: textView, clip: try #require(textView.enclosingScrollView?.contentView),
                rendered: try #require(gutter.rendered))
        }
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
