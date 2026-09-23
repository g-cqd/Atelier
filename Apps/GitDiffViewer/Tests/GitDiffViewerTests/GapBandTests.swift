import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The empty band a gap takes on its boundary, as in Xcode (book DIFF-02): how the layouts and the panes size and
/// place it, and that nothing of a row reaches into it.
@MainActor
struct GapBandTests {
    /// Forty lines changed at lines 12 and 30: a leading gap, a gap between the changes, and a trailing gap, each
    /// with a band.
    private func text(
        sides: DiffRenderer.Options = DiffRenderer.Options(), context: Int = 2, multiple: Double = 0
    ) -> RenderedDiff {
        let old = (1 ... 40).map { "let value\($0) = \($0)" }
        var new = old
        for line in [11, 29] { new[line] = "let value\(line + 1) = changed" }
        return DiffRenderer.render(
            oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
            language: .plain, lineHeightMultiple: multiple, layout: .changes(context: context, expansions: [:]))
    }

    @Test(arguments: [0.0, 1.3])
    func `an unwrapped layout is as tall as its rows and its gaps' bands`(multiple: Double) throws {
        let rendered = try #require(text(multiple: multiple).new)
        let sut = StaticTextLayout(rendered: rendered)
        sut.layOut(mode: .none, viewportWidth: 400)

        let bands = CGFloat(rendered.gaps.count(where: \.hasBand)) * rendered.gapBandHeight
        #expect(sut.height == (CGFloat(rendered.rows.count) * rendered.lineHeight + bands).rounded(.up))
    }

    @Test(arguments: [0.0, 1.3])
    func `an unwrapped layout's height is the one TextKit lays out, bands included`(multiple: Double) throws {
        let rendered = try #require(text(multiple: multiple).new)
        let analytic = StaticTextLayout(rendered: rendered)
        analytic.layOut(mode: .none, viewportWidth: 400)
        let laidOut = StaticTextLayout(rendered: rendered)
        laidOut.layOut(mode: .column(100_000), viewportWidth: 400)

        #expect(analytic.height == laidOut.height)
    }

    @Test
    func `a layout keeps the bands at the top and the end of the file as its insets`() throws {
        let rendered = try #require(text().new)
        let sut = StaticTextLayout(rendered: rendered)

        #expect(sut.inset == rendered.gapBandHeight)
        #expect(sut.bottomInset == rendered.gapBandHeight)
    }

    @Test
    func `the rows' own heights leave the bands out`() throws {
        let rendered = try #require(text().new)
        let sut = StaticTextLayout(rendered: rendered)
        sut.layOut(mode: .viewport, viewportWidth: 4_000)

        #expect(sut.rowHeights() == Array(repeating: Double(rendered.lineHeight), count: rendered.rows.count))
    }

    /// A split card whose first row, line 12, wraps on the new side only, with a band under it: no context, and a
    /// second change at line 30, so a gap lies between the two rows.
    private func wrappingCard() throws -> (card: CardLayouts, left: StaticTextLayout, right: StaticTextLayout) {
        let old = (1 ... 40).map { "let value\($0) = \($0)" }
        var new = old
        new[11] = "let value12 = " + String(repeating: "wrapped ", count: 30)
        new[29] = "let value30 = changed"
        let card = CardLayouts(
            rendered: DiffRenderer.render(
                oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
                language: .plain, layout: .changes(context: 0, expansions: [:])))
        let left = try #require(card.old)
        let right = try #require(card.new)
        try #require(left.rendered.bandSpacing(afterRow: 0) > 0)
        return (card, left, right)
    }

    @Test
    func `aligning a wrapped split card adds the alignment on top of a band`() throws {
        let sut = try wrappingCard()

        sut.card.prepareSplit(width: 200, mode: .viewport)

        let band = sut.left.rendered.gapBandHeight
        let shortfall = CGFloat(sut.right.rowHeights()[0] - sut.left.rowHeights()[0])
        #expect(shortfall > 0)
        #expect(spacing(afterRow: 0, in: sut.left) == band + shortfall)
        #expect(spacing(afterRow: 0, in: sut.right) == band)
        #expect(sut.left.height == sut.right.height)
    }

    @Test
    func `dropping the alignment keeps the bands`() throws {
        let sut = try wrappingCard()

        sut.card.prepareSplit(width: 200, mode: .viewport)
        sut.card.prepareSplit(width: 200, mode: .none)

        let band = sut.left.rendered.gapBandHeight
        #expect(spacing(afterRow: 0, in: sut.left) == band)
        #expect(spacing(afterRow: 0, in: sut.right) == band)
    }

    @Test
    func `a band after a changed row stays the text's own background`() throws {
        // With no context, the row above the band between the changes is the first change itself.
        let rendered = try #require(text(context: 0).new)
        let between = try #require(rendered.gaps.first { $0.boundary > 0 && $0.boundary < rendered.rows.count })
        try #require(rendered.rows[between.boundary - 1].kind != .context)
        let pane = try CardPaneFixture(rendered: rendered)
        let bandTop = pane.layout.inset + CGFloat(between.boundary) * rendered.lineHeight

        // The changed row's own colour, then the band under it, then the text's background past the text.
        let row = pane.pixel(at: NSPoint(x: 200, y: bandTop - rendered.lineHeight / 2))
        let band = pane.pixel(at: NSPoint(x: 200, y: bandTop + rendered.gapBandHeight / 2))
        let background = pane.pixel(at: NSPoint(x: 200, y: pane.textView.frame.maxY - 1))

        #expect(row != background)
        #expect(band == background)
    }

    @Test
    func `a card pane insets its text by the band above its first row`() throws {
        let rendered = try #require(text().new)
        let pane = try CardPaneFixture(rendered: rendered)
        #expect(pane.textView.textContainerInset.height == rendered.gapBandHeight)
    }

    @Test
    func `a file pane's band above its first row takes the place of its own inset`() throws {
        let rendered = try #require(text(sides: DiffRenderer.Options(sides: [.unified])).unified)
        let scrollView = NSTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? NSTextView)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView

        sut.apply(rendered)

        #expect(textView.textContainerInset.height == max(DiffPaneMetrics.containerInset, rendered.gapBandHeight))
    }

    @Test
    func `scrolled to its end, a file pane shows its last line at its top and the end's band under it`() throws {
        let rendered = try #require(text(sides: DiffRenderer.Options(sides: [.unified])).unified)
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let textView = try #require(scrollView.documentView as? NSTextView)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView
        sut.wrapsLines = false
        DiffTextViewCoordinator.configureWrapping(
            false, column: 0, font: rendered.palette.font, textView: textView, scrollView: scrollView)
        sut.apply(rendered)
        sut.updateOverscroll(in: scrollView.contentView)

        let lastLineTop = textView.textContainerInset.height + rendered.unwrappedTextHeight - rendered.lineHeight
        let endOffset = textView.frame.height - scrollView.contentView.bounds.height
        #expect(lastLineTop >= endOffset)
        #expect(lastLineTop - endOffset < 1)
    }

    /// The paragraph spacing after `row` in `layout`'s storage.
    private func spacing(afterRow row: Int, in layout: StaticTextLayout) -> CGFloat {
        guard let storage = layout.contentStorage.textStorage else { return -1 }
        let style = storage.attribute(.paragraphStyle, at: layout.rendered.lineStarts[row], effectiveRange: nil)
        return (style as? NSParagraphStyle)?.paragraphSpacing ?? -1
    }
}

/// A card pane's text view showing a detached layout, as ``EmbeddedDiffTextView`` shows one, in an offscreen window.
@MainActor
private struct CardPaneFixture {
    let layout: StaticTextLayout
    let textView = NSTextView(usingTextLayoutManager: true)
    let window: NSWindow

    init(rendered: RenderedText) throws {
        layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 400)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = true
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: layout.height)
        window = NSWindow(contentRect: textView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(textView)
        let coordinator = EmbeddedDiffTextView.Coordinator()
        coordinator.textView = textView
        coordinator.attach(layout)
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
    }

    /// The text view's pixel at `point`, as it draws now.
    func pixel(at point: NSPoint) -> NSColor? {
        guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
        let scale = window.backingScaleFactor
        return bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
    }
}
