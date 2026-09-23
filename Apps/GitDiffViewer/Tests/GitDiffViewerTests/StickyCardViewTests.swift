import AppKit
import Testing

@testable import DiffTextKit

@MainActor
private final class WindowRetainer {
    private var windows: [NSWindow] = []
    func append(_ window: NSWindow) { windows.append(window) }
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

/// A 300 pt card with a 30 pt header, placed at y = 100 of a scrolling document by a host view (the way SwiftUI
/// places it), in a 400 pt scroll view whose top 52 pt sit under bars.
@MainActor
struct StickyCardViewTests {
    private let topInset: CGFloat = 52
    private let gap: CGFloat = 16
    private let retainedWindows = WindowRetainer()

    private struct SUT {
        let scrollView: NSScrollView
        let host: NSView
        let card: StickyCardView
        let header: NSView
    }

    private func makeSUT(cardHeight: CGFloat = 300, inScrollView: Bool = true) -> SUT {
        let header = NSView()
        let card = StickyCardView(header: header, body: NSView())
        card.headerHeight = 30
        card.stickyGap = gap
        let host = NSView(frame: NSRect(x: 10, y: 100, width: 380, height: cardHeight))
        card.frame = host.bounds
        host.addSubview(card)
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 400, height: 2000))
        document.addSubview(host)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        scrollView.documentView = document
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(inScrollView ? scrollView : document)
        retainedWindows.append(window)
        let sut = SUT(scrollView: scrollView, host: host, card: card, header: header)
        scroll(sut, toVisibleTop: 0)
        card.layoutSubtreeIfNeeded()
        return sut
    }

    /// Scrolls so the first row below the bars is `y` of the document.
    private func scroll(_ sut: SUT, toVisibleTop y: CGFloat) {
        sut.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y - topInset))
        sut.scrollView.reflectScrolledClipView(sut.scrollView.contentView)
    }

    /// Where the header shows, in the scrolling document.
    private func headerInDocument(_ sut: SUT) -> CGRect {
        sut.card.convert(sut.card.headerFrame, to: sut.host.superview)
    }

    @Test
    func `a card below the pin line rests at its own top with no hairline`() {
        let sut = makeSUT()
        #expect(sut.card.appliedGeometry?.offset == 0)
        #expect(sut.card.headerFrame == CGRect(x: 0, y: 0, width: 380, height: 30))
        #expect(!sut.card.isHairlineVisible)
    }

    @Test(arguments: [150, 200.5, 330] as [CGFloat])
    func `a card scrolled past the pin line keeps its header the gap below the bars`(visibleTop: CGFloat) {
        let sut = makeSUT()
        scroll(sut, toVisibleTop: visibleTop)
        #expect(headerInDocument(sut).minY == visibleTop + gap)
        #expect(sut.card.appliedGeometry?.offset == visibleTop + gap - 100)
        #expect(sut.card.isHairlineVisible)
    }

    @Test
    func `the card's bottom pushes its header out`() {
        let sut = makeSUT()
        scroll(sut, toVisibleTop: 600)
        #expect(sut.card.headerFrame == CGRect(x: 0, y: 270, width: 380, height: 30))
        #expect(headerInDocument(sut).maxY == 400)
    }

    @Test
    func `scrolling back above the pin line returns the card to rest and hides the hairline`() {
        let sut = makeSUT()
        scroll(sut, toVisibleTop: 200)
        scroll(sut, toVisibleTop: 0)
        #expect(sut.card.appliedGeometry?.offset == 0)
        #expect(!sut.card.isHairlineVisible)
    }

    @Test
    func `moving the host re-places the card without any scroll`() {
        let sut = makeSUT()
        sut.host.setFrameOrigin(NSPoint(x: 10, y: -50))
        #expect(sut.card.appliedGeometry?.offset == gap + 50)
        #expect(headerInDocument(sut).minY == gap)
    }

    @Test
    func `a folded card, only a header tall, never pins`() {
        let sut = makeSUT(cardHeight: 30)
        scroll(sut, toVisibleTop: 200)
        #expect(sut.card.appliedGeometry?.offset == 0)
        #expect(!sut.card.isHairlineVisible)
    }

    @Test
    func `outside a scroll view a card stays at rest`() {
        let sut = makeSUT(inScrollView: false)
        sut.host.setFrameOrigin(NSPoint(x: 10, y: -200))
        #expect(sut.card.appliedGeometry?.offset == 0)
    }

    @Test
    func `the area a pinned header left above it takes no clicks, and the header does`() {
        let sut = makeSUT()
        scroll(sut, toVisibleTop: 200)
        let offset = sut.card.appliedGeometry?.offset ?? 0
        // `hitTest(_:)` takes its point in the superview's coordinates, which are not flipped.
        let above = sut.card.convert(NSPoint(x: 20, y: offset - 10), to: sut.host)
        let onHeader = sut.card.convert(NSPoint(x: 20, y: offset + 10), to: sut.host)
        #expect(sut.card.hitTest(above) == nil)
        #expect(sut.card.hitTest(onHeader) === sut.header)
    }
}
