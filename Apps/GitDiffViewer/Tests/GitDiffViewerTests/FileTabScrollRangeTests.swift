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
/// pane's top (book DIFF-08). Either way each pane's text view covers its text: a pane sized while TextKit had laid
/// nothing out ended above its text and did not scroll (`FilePaneScrollRangeTests`).
///
/// The tests share one window, as the app keeps one while its explorers move and its layout changes. Making the whole
/// window, its toolbar above all, and laying it out the first time took about 0.7 s of main-thread time, which each
/// test paid and the suite's 1 s budget could not (`scripts/main-actor-budget.sh`). They run one at a time, each from
/// the file list with no tab open.
@MainActor
@Suite(.mainActorLane, .serialized)
struct FileTabScrollRangeTests {
    private static let session = WindowSession()

    @Test
    func `a file opened from the list shows whole when it fits, else from its first change`() async throws {
        let (model, content) = try await Self.session.fileList(placement: .sidebar, mode: .inline)
        #expect(model.detailState == .cards)

        model.select("short.swift")
        try await Self.session.settle()
        try Self.expectWhole(in: content, "explorers in the sidebar, inline, opened by a click")

        model.settings.mode = .split
        model.pin("long.swift")
        try await Self.session.settle()
        try Self.expectFirstChange(
            of: model, in: content, "explorers in the sidebar, side by side, opened by a double click")

        // Both tabs close before the window is drawn again: the file list between them is not what this test reads.
        model.settings.explorerPlacement = .top
        model.closeTab(try #require(model.tabs.active).id)
        model.closeTab(try #require(model.tabs.active).id)
        try await Self.session.settle()
        model.pin("short.swift")
        try await Self.session.settle()
        try Self.expectWhole(in: content, "explorers above, side by side, opened by a double click")

        model.settings.mode = .inline
        model.select("long.swift")
        try await Self.session.settle()
        try Self.expectFirstChange(of: model, in: content, "explorers above, inline, opened by a click")
    }

    /// A tab shown again after the file list comes back where its panes were, not to its first change (book TAB-10,
    /// DIFF-08): side by side with the explorers in the sidebar, then inline with them above.
    @Test
    func `a file tab shown again comes back where it was scrolled, not to its first change`() async throws {
        let (model, content) = try await Self.session.fileList(placement: .sidebar, mode: .split)

        let layouts = [(ExplorerPlacement.sidebar, ViewMode.split), (.top, .inline)]
        for (index, (placement, mode)) in layouts.enumerated() {
            let comment: Comment = "explorers \(placement.rawValue), \(mode.rawValue)"
            model.settings.explorerPlacement = placement
            model.settings.mode = mode
            model.pin("long.swift")
            try await Self.session.settle()
            try Self.expectFirstChange(of: model, in: content, comment)
            for pane in try Self.panes(in: content) { Self.scroll(pane, to: 555) }
            try await Self.session.settle()
            let before = try Self.panes(in: content).map { try Self.topRow(of: $0) }

            model.showFileList()
            try await Self.session.settle()
            model.activateTab(try #require(model.tabs.active?.id ?? model.tabs.tabs.first?.id))
            try await Self.session.settle()

            #expect(model.scrollRequest == nil, comment)
            let after = try Self.panes(in: content).map { try Self.topRow(of: $0) }
            #expect(after.map(\.row) == before.map(\.row), comment)
            for (was, now) in zip(before, after) { #expect(abs(was.offset - now.offset) < 1, comment) }
            // The next layout opens the file afresh; after the last, the next test closes the tab.
            guard index < layouts.count - 1 else { continue }
            model.closeTab(try #require(model.tabs.active).id)
            try await Self.session.settle()
        }
    }

    static func scroll(_ pane: ShownPane, to y: CGFloat) {
        pane.clip.scroll(to: NSPoint(x: 0, y: y))
        pane.clip.enclosingScrollView?.reflectScrolledClipView(pane.clip)
    }

    /// The row at the top of `pane`, and how far into its line the pane is scrolled.
    static func topRow(of pane: ShownPane) throws -> (row: Int, offset: CGFloat) {
        let layoutManager = try #require(pane.textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let origin = pane.textView.textContainerOrigin.y
        let fragment = try #require(
            layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: pane.shownTop - origin)))
        let row = pane.rendered.rowIndex(
            containing: content.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        )
        return (row, pane.shownTop - origin - fragment.layoutFragmentFrame.minY)
    }

    static func text(_ lines: [String], changing changed: Int? = nil) -> String {
        var lines = lines
        if let changed { lines[changed] = "let changed = true" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Each file pane shows the row the model asked for three lines below its top, and covers its text.
    private static func expectFirstChange(of model: DiffViewerModel, in content: NSView, _ comment: Comment) throws {
        let row = try #require(model.scrollRequest?.row, comment)
        for pane in try panes(in: content) {
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
            let below = try pane.top(ofRow: row) - pane.shownTop
            #expect(abs(below - 3 * pane.lineHeight) < 1, "\(comment): the row is \(below) below the pane's top")
        }
    }

    /// Each file pane shows its text whole, from its top, its text view filling the pane.
    static func expectWhole(in content: NSView, _ comment: Comment) throws {
        for pane in try panes(in: content) {
            #expect(pane.shownTop == 0, comment)
            #expect(pane.textView.frame.height >= pane.shownHeight, comment)
            #expect(pane.textView.frame.height >= pane.rowsHeight, comment)
            #expect(try pane.bottom(ofRow: pane.lastRow) + pane.below <= pane.clip.bounds.maxY, comment)
        }
    }

    /// The file panes: the text views that scroll, which a card's do not.
    static func panes(in content: NSView) throws -> [ShownPane] {
        let textViews = subviews(of: DiffPaneTextView.self, in: content).filter { $0.enclosingScrollView != nil }
        try #require(!textViews.isEmpty)
        return try textViews.map { textView in
            let gutter = try #require(
                subviews(of: DiffGutterView.self, in: content)
                    .first { ($0.source as? TextKit2RowGeometry)?.textView === textView })
            return ShownPane(
                textView: textView, clip: try #require(textView.enclosingScrollView?.contentView),
                rendered: try #require(gutter.rendered))
        }
    }

    /// The window's content, toolbar and explorers included, as the app makes it, in a window that is never ordered in.
    fileprivate static func window(showing model: DiffViewerModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(settings: model.settings, model: model))
        return window
    }

    fileprivate static func draw(_ window: NSWindow) {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }
}

extension FileTabScrollRangeTests {
    /// The suite's window, made on its first test and kept for the rest, over a model of `long.swift`, 200 lines
    /// changed at the 121st, and `short.swift`, which fits a pane. Nested in the suite, so that
    /// `scripts/main-actor-budget.sh` counts its main-thread time as the suite's.
    @MainActor
    fileprivate final class WindowSession {
        private let harness = ModelTestHarness()
        private var shown: (model: DiffViewerModel, window: NSWindow)?

        /// The model and the window's content, on the file list with no tab open, the explorers at `placement` and the
        /// files shown in `mode`, once the window has settled.
        func fileList(placement: ExplorerPlacement, mode: ViewMode) async throws -> (DiffViewerModel, NSView) {
            let (model, window) = try await start(placement: placement, mode: mode)
            for tab in model.tabs.tabs { model.closeTab(tab.id) }
            model.showFileList()
            model.settings.explorerPlacement = placement
            model.settings.mode = mode
            try await settle()
            return (model, try #require(window.contentView))
        }

        /// Lets every task the model spawned end, then lays out and draws the window, with one turn of the run loop.
        func settle() async throws {
            try await harness.taskProvider.waitForAllTasks()
            if let window = shown?.window { FileTabScrollRangeTests.draw(window) }
        }

        /// The shared model and window, made and loaded on the first call, with the settings it asks for.
        private func start(
            placement: ExplorerPlacement, mode: ViewMode
        ) async throws -> (model: DiffViewerModel, window: NSWindow) {
            if let shown { return shown }
            let short = (1 ... 10).map { "let value\($0) = \($0)" }
            let long = (1 ... 200).map { "let value\($0) = \($0)" }
            harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
                harness.entry("long.swift", "3"), harness.entry("short.swift", "1")
            ]
            harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
                harness.entry("long.swift", "4"), harness.entry("short.swift", "2")
            ]
            harness.reader.blobContents["1"] = FileTabScrollRangeTests.text(short)
            harness.reader.blobContents["2"] = FileTabScrollRangeTests.text(short, changing: 9)
            harness.reader.blobContents["3"] = FileTabScrollRangeTests.text(long)
            harness.reader.blobContents["4"] = FileTabScrollRangeTests.text(long, changing: 120)
            let model = harness.makeSUT()
            model.settings.explorerPlacement = placement
            model.settings.mode = mode
            let window = FileTabScrollRangeTests.window(showing: model)
            try await harness.load(model)
            let started = (model: model, window: window)
            shown = started
            return started
        }
    }
}
