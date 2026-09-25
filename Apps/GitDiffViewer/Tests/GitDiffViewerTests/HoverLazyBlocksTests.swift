import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A long discussion builds the blocks the panel shows at once and the rest as the body scrolls to them: every block
/// is a view measured and laid out, and a few hundred of them held the main thread for seconds (`HoverBuildBenchmark`).
@MainActor
struct HoverLazyBlocksTests {
    private static func prose(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }

    private static func document(paragraphs: Int) -> HoverDocument {
        HoverDocument(
            summary: prose("Loads the configuration."),
            discussion: (0 ..< paragraphs).map { .paragraph(prose("Paragraph \($0) of the discussion.")) })
    }

    private static func preparedPanel(for document: HoverDocument) throws -> HoverDocPanel {
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(document: document, appearance: try #require(NSAppearance(named: .aqua)))
        return panel
    }

    @Test
    func `a long discussion builds what the panel shows, and the rest as the body scrolls to it`() throws {
        let panel = try Self.preparedPanel(for: Self.document(paragraphs: 120))
        // The Overview heading, then the paragraphs.
        let built = panel.shownBlockViews.count
        #expect(built < 121)
        #expect(panel.panelHeightForTests == HoverPanelSizing.maxHeight)

        panel.scrollThroughDiscussion()

        #expect(panel.shownBlockViews.count == 121)
        panel.bodyStack.layoutSubtreeIfNeeded()
        #expect(abs(panel.bodyDocument.frame.height - panel.bodyStack.fittingSize.height) < 1)
    }

    @Test
    func `a discussion that fits is built whole at once`() throws {
        let panel = try Self.preparedPanel(for: Self.document(paragraphs: 3))

        #expect(panel.shownBlockViews.count == 4)
        #expect(panel.pendingDiscussion == nil)
    }

    @Test
    func `a new document drops the blocks the last one had left to build`() throws {
        let panel = try Self.preparedPanel(for: Self.document(paragraphs: 120))
        #expect(panel.pendingDiscussion != nil)

        panel.prepareOffscreenForTests(
            document: Self.document(paragraphs: 2), appearance: try #require(NSAppearance(named: .aqua)))

        #expect(panel.pendingDiscussion == nil)
        #expect(panel.shownBlockViews.count == 3)
    }

    @Test
    func `a long code block is measured and shown as far as the body scrolls to it`() throws {
        let lines = (0 ..< 600).map { "let value\($0) = compute(\($0), scale: \($0 % 7))" }
        let code = NSAttributedString(
            string: lines.joined(separator: "\n"),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)])
        let panel = try Self.preparedPanel(
            for: HoverDocument(
                summary: Self.prose("Loads."), discussion: [.code(code), .paragraph(Self.prose("After it."))]))
        let chip = try #require(
            panel.shownBlockViews.compactMap { $0 as? NSBox }.first { $0.boxType == NSBox.BoxType.custom })
        let codeView = try #require(Self.textViews(under: chip).first)
        #expect(codeView.string.split(separator: "\n").count < 600)

        panel.scrollThroughDiscussion()

        #expect(codeView.string == code.string)
        #expect(panel.shownBlockViews.count == 3)
        panel.bodyStack.layoutSubtreeIfNeeded()
        let innerWidth =
            HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset - 2 * HoverPanelMetrics.chipHorizontalPadding
        let whole =
            HoverDocPanel.measuredHeight(of: code, width: innerWidth) + 2 * HoverPanelMetrics.chipVerticalPadding
        #expect(abs(chip.frame.height - whole) < 1)
        #expect(abs(panel.bodyDocument.frame.height - panel.bodyStack.fittingSize.height) < 1)
    }

    private static func textViews(under root: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        var pending = [root]
        while let view = pending.popLast() {
            if let textView = view as? NSTextView { found.append(textView) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }
}

extension HoverDocPanel {
    /// Scrolls the body to its end until every block of the discussion is built, as a reader scrolling through does;
    /// gives up after a hundred scrolls.
    func scrollThroughDiscussion() {
        let clip = bodyScrollView.contentView
        var scrolls = 0
        while pendingDiscussion != nil, scrolls < 100 {
            clip.scroll(to: NSPoint(x: 0, y: max(bodyDocument.frame.height - clip.bounds.height, 0)))
            scrolls += 1
        }
    }
}
