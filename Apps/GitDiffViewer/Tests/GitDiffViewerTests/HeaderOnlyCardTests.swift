import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffTextKit
@testable import GitDiffViewer

/// In the card list, a file renamed without changes is its header alone: no seam, no pane, nothing to unfold (book
/// DIFF-07, criterion 4).
@MainActor
@Suite(.mainActorLane)
struct HeaderOnlyCardTests {
    private let harness = ModelTestHarness()

    @Test
    func `a card renamed without changes is as tall as its header, with no body`() async throws {
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("old/name.swift", "1"), harness.entry("a.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("new/name.swift", "1"), harness.entry("a.swift", "3")
        ]
        harness.reader.blobContents = ["1": "one\ntwo\n", "2": "alpha\n", "3": "beta\n"]
        let sut = harness.makeSUT()
        let list = CardList(model: sut)
        defer { list.close() }
        try await harness.load(sut)
        list.pump()

        let paths = sut.renderedFiles.map(\.path)
        let cards = list.cards()
        try #require(cards.count == paths.count)
        let renamed = try #require(paths.firstIndex(of: "old/name.swift").map { cards[$0] })
        let changed = try #require(paths.firstIndex(of: "a.swift").map { cards[$0] })
        #expect(renamed.headerHeight > 0)
        #expect(renamed.bodyHeight == 0)
        #expect(renamed.bounds.height == renamed.headerHeight)
        // The same measure sees the body of a card that has one.
        #expect(changed.bodyHeight > 0)
        #expect(changed.bounds.height > changed.headerHeight)
    }
}

/// The card list of a model, in a window that is never ordered in.
@MainActor
private final class CardList {
    private let window: NSWindow

    init(model: DiffViewerModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.borderless], backing: .buffered,
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
        var found: [StickyCardView] = []
        var pending: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = pending.popLast() {
            if let card = view as? StickyCardView { found.append(card) }
            pending.append(contentsOf: view.subviews)
        }
        // Window coordinates grow upward.
        return found.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
    }
}
