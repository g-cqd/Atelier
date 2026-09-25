import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Panes that never wrap size themselves from their rows, never from a whole-document layout.
@MainActor
@Suite(.mainActorLane)
struct NoWrapLayoutTests {
    private let old = (1 ... 60).map { "let value\($0) = \($0)\n" }.joined()
    private var new: String {
        old.replacingOccurrences(of: "let value30 = 30\n", with: "let renamedValue30 = 30 // changed\n")
            .replacingOccurrences(of: "let value45 = 45\n", with: "")
    }

    private func rendered(layout: RenderLayout = .changes(context: 3, expansions: [:])) -> RenderedDiff {
        DiffRenderer.render(oldText: old, newText: new, language: .plain, lineHeightMultiple: 1.2, layout: layout)
    }

    @Test(arguments: [RenderLayout.full, .changes(context: 3, expansions: [:])])
    func `the unwrapped height needs no layout and matches TextKit's`(layout: RenderLayout) throws {
        let text = try #require(rendered(layout: layout).unified)
        let analytic = StaticTextLayout(rendered: text)
        analytic.layOut(mode: .none, viewportWidth: 300)
        let laidOut = StaticTextLayout(rendered: text)
        laidOut.layOut(mode: .column(100_000), viewportWidth: 300)
        #expect(analytic.height == laidOut.height)
    }

    @Test
    func `an unwrapped layout is as wide as its longest line or the pane, whichever is wider`() throws {
        let text = try #require(rendered().unified)
        let sut = StaticTextLayout(rendered: text)
        sut.layOut(mode: .none, viewportWidth: 20)
        #expect(sut.contentWidth == text.measuredUnwrappedWidth())
        sut.layOut(mode: .none, viewportWidth: 5000)
        #expect(sut.contentWidth == 5000)
    }

    @Test
    func `an ASCII text measures one cell per character`() throws {
        let text = try #require(rendered().unified)
        #expect(text.measuredUnwrappedWidth() == text.unwrappedWidth.rounded(.up) + 1)
    }

    @Test
    func `wide characters widen the unwrapped width to what they draw`() throws {
        let line = String(repeating: "漢字", count: 20)
        let text = try #require(
            DiffRenderer.render(oldText: "a\n", newText: "a\n\(line)\n", language: .plain).unified)
        let drawn = try #require(text.attributed.string.components(separatedBy: "\n").firstIndex(of: line))
        let range = NSRange(location: text.lineStarts[drawn], length: (line as NSString).length)
        let width = text.attributed.attributedSubstring(from: range).size().width
        #expect(text.measuredUnwrappedWidth() > text.unwrappedWidth)
        #expect(text.measuredUnwrappedWidth() >= width + 2 * DiffPaneMetrics.lineFragmentPadding)
    }

    @Test
    func `switching a split card to no wrap drops the alignment wrapping added`() throws {
        let long = String(repeating: "wrapping ", count: 30)
        let diff = DiffRenderer.render(oldText: "short\n", newText: "\(long)\n", language: .plain)
        let sut = CardLayouts(rendered: diff)
        let sides = try [#require(sut.old), #require(sut.new)]
        sut.prepareSplit(width: 120, mode: .viewport)
        #expect(sides.contains { spacings(in: $0).contains { $0 > 0 } })
        sut.prepareSplit(width: 120, mode: .none)
        #expect(sides.allSatisfy { spacings(in: $0).allSatisfy { $0 == 0 } })
    }

    @Test
    func `a file pane that never wraps tracks its view, as wide as its longest line and as tall as its rows lay out`()
        throws
    {
        let text = try #require(rendered().unified)
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let textView = try #require(scrollView.documentView as? NSTextView)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView
        sut.wrapsLines = false
        sut.scrollsPastEnd = true
        DiffTextViewCoordinator.configureWrapping(
            false, column: 0, font: text.palette.font, textView: textView, scrollView: scrollView)
        sut.apply(text)
        // The height is TextKit's; laid out whole, as scrolling through the pane lays it out, it is the rows'.
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        sut.updateOverscroll(in: scrollView.contentView)

        let clip = scrollView.contentView.bounds
        // The rows and the gaps' bands between them; above, the band of a gap at the top in place of the pane's inset;
        // below, the band of a gap at the end, then the pane's inset.
        let top = max(DiffPaneMetrics.containerInset, text.bandAbove)
        let rows = top + text.unwrappedTextHeight + text.bandBelow + DiffPaneMetrics.containerInset
        #expect(text.bandAbove > DiffPaneMetrics.containerInset)
        #expect(textView.textContainer?.widthTracksTextView == true)
        #expect(!textView.isHorizontallyResizable)
        let overscroll = max(clip.height - text.lineHeight - text.bandBelow - DiffPaneMetrics.containerInset, 0)
        #expect(textView.frame.height == (rows + overscroll).rounded(.up))
        #expect(textView.frame.width == max(clip.width, text.measuredUnwrappedWidth()))
    }

    private func spacings(in layout: StaticTextLayout) -> [CGFloat] {
        guard let storage = layout.contentStorage.textStorage else { return [] }
        return layout.rendered.lineStarts.compactMap { start in
            guard start < storage.length else { return nil }
            return (storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle)?
                .paragraphSpacing
        }
    }
}
