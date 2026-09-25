import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A panel a pane reuses shows each document in the block views the last one left, where the kinds match: removing
/// a few hundred views from the body's stack held the main thread for 60 to 360 ms (`HoverBuildBenchmark`).
@MainActor
struct HoverBlockReuseTests {
    private static func prose(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }

    private static func document(_ discussion: [HoverDocument.Block]) -> HoverDocument {
        HoverDocument(summary: prose("Loads the configuration."), discussion: discussion)
    }

    private static func paragraphs(_ count: Int, saying word: String) -> [HoverDocument.Block] {
        (0 ..< count).map { .paragraph(prose("\(word) paragraph \($0) of the discussion.")) }
    }

    private static func prepare(_ panel: HoverDocPanel, with document: HoverDocument) throws {
        panel.prepareOffscreenForTests(document: document, appearance: try #require(NSAppearance(named: .aqua)))
    }

    @Test
    func `a new document shows its blocks in the views of the last one's blocks of the same kind`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        try Self.prepare(panel, with: Self.document(Self.paragraphs(3, saying: "First")))
        let before = panel.shownBlockViews

        try Self.prepare(panel, with: Self.document(Self.paragraphs(3, saying: "Second")))

        let after = panel.shownBlockViews
        #expect(after.count == 4)
        #expect(zip(before, after).allSatisfy { $0 === $1 })
        let texts = after.dropFirst().compactMap { ($0 as? NSTextView)?.string }
        #expect(texts == (0 ..< 3).map { "Second paragraph \($0) of the discussion." })
    }

    @Test
    func `a block of another kind gets a view of its own kind`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        try Self.prepare(panel, with: Self.document(Self.paragraphs(2, saying: "First")))
        let before = panel.shownBlockViews

        try Self.prepare(panel, with: Self.document([.paragraph(Self.prose("Kept.")), .rule]))

        let after = panel.shownBlockViews
        #expect(after.count == 3)
        #expect(after[1] === before[1])
        #expect(after[2] !== before[2])
        #expect((after[2] as? NSBox)?.boxType == .separator)
    }

    @Test
    func `a shorter document after a longer one shows its own blocks alone, the body sized to them`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        try Self.prepare(panel, with: Self.document(Self.paragraphs(120, saying: "Long")))
        panel.scrollThroughDiscussion()

        try Self.prepare(panel, with: Self.document(Self.paragraphs(2, saying: "Short")))

        #expect(panel.shownBlockViews.count == 3)
        #expect(panel.bodyEndsWithItsLastBlock)
        let texts = panel.shownBlockViews.dropFirst().compactMap { ($0 as? NSTextView)?.string }
        #expect(texts == ["Short paragraph 0 of the discussion.", "Short paragraph 1 of the discussion."])
    }

    @Test
    func `a longer document after a shorter one builds the rest as the body scrolls to it`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        try Self.prepare(panel, with: Self.document(Self.paragraphs(120, saying: "Long")))
        panel.scrollThroughDiscussion()
        try Self.prepare(panel, with: Self.document(Self.paragraphs(2, saying: "Short")))

        try Self.prepare(panel, with: Self.document(Self.paragraphs(120, saying: "Again")))
        panel.scrollThroughDiscussion()

        #expect(panel.shownBlockViews.count == 121)
        #expect(panel.bodyEndsWithItsLastBlock)
        #expect((panel.shownBlockViews.last as? NSTextView)?.string == "Again paragraph 119 of the discussion.")
    }
}

extension HoverDocPanel {
    /// The body's block views the discussion shows, top to bottom, the Overview heading first; hidden ones wait to be
    /// reused.
    var shownBlockViews: [NSView] {
        bodyDocument.layoutSubtreeIfNeeded()
        return bodyDocument.subviews.filter { !$0.isHidden }.sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Whether the body's document ends where its last block shown does, once laid out.
    var bodyEndsWithItsLastBlock: Bool {
        abs(bodyDocument.frame.height - (shownBlockViews.last?.frame.maxY ?? 0)) < 1
    }
}
