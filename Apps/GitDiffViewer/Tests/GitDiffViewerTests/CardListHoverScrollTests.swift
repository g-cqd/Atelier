import AemiTesting
import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

@MainActor
private final class WindowRetainer {
    private var windows: [NSWindow] = []
    func append(_ window: NSWindow) { windows.append(window) }
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

/// The hover panel of a card pane, whose text view sits in its own sideways scroll view inside the card list's
/// scroll view: scrolling the list moves the panel with its identifier, and closes it once the identifier leaves the
/// list's visible area or slides under the card's pinned header (HOVER-09).
@MainActor
struct CardListHoverScrollTests {
    private let retainedWindows = WindowRetainer()
    private let clock = TestClock()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let debounce: Duration = .milliseconds(300)
    /// Where the card sits in the list's document.
    private let cardTop: CGFloat = 100
    private let headerHeight: CGFloat = 30

    private struct SUT {
        let list: NSScrollView
        let textView: NSTextView
        let window: NSWindow
        let controller: DocHoverController
        let rendered: RenderedText
    }

    private func rendered() throws -> RenderedText {
        let text = (0 ..< 40).map { "let identifier\($0) = \($0)\n" }.joined()
        return try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
    }

    /// A text view laid out for `rendered`, in a sideways-only scroll view the way a card pane hosts it.
    private func pane(showing rendered: RenderedText) -> (scrollView: NSScrollView, textView: NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        let height = rendered.lineHeight * CGFloat(rendered.rows.count) + 2 * DiffPaneMetrics.containerInset
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: height)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: height))
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    /// A 300 pt tall card list in a window in the middle of the screen, holding one card at ``cardTop``: a header
    /// ``headerHeight`` tall above the pane.
    private func makeSUT() throws -> SUT {
        let rendered = try rendered()
        let (paneScrollView, textView) = pane(showing: rendered)
        let card = StickyCardView(header: NSView(), body: paneScrollView)
        card.headerHeight = headerHeight
        card.bodyHeight = paneScrollView.frame.height
        card.stickyGap = 0
        let host = NSView(
            frame: NSRect(x: 0, y: cardTop, width: 800, height: headerHeight + paneScrollView.frame.height))
        card.frame = host.bounds
        host.addSubview(card)
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 800, height: 3000))
        document.addSubview(host)
        let list = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        list.automaticallyAdjustsContentInsets = false
        list.hasVerticalScroller = true
        list.documentView = document
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 800, height: 300), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView?.addSubview(list)
        retainedWindows.append(window)
        card.layoutSubtreeIfNeeded()

        let controller = DocHoverController(clock: clock, taskProvider: taskProvider, debounce: debounce)
        controller.resolve = { _ in HoverDocument(summary: NSAttributedString(string: "docs")) }
        controller.attach(to: textView) { rendered }
        return SUT(list: list, textView: textView, window: window, controller: controller, rendered: rendered)
    }

    /// Column 8 of `row`, inside that row's identifier, in the text view's coordinates.
    private func point(row: Int, in sut: SUT) -> NSPoint {
        let charWidth = ("0" as NSString).size(withAttributes: [.font: sut.rendered.palette.font]).width
        return NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + 8.5 * charWidth,
            y: DiffPaneMetrics.containerInset + (CGFloat(row) + 0.5) * sut.rendered.lineHeight)
    }

    /// Rests the pointer on `row`'s identifier until the panel shows.
    private func showPanel(row: Int, in sut: SUT) async throws {
        sut.controller.pointerMoved(to: point(row: row, in: sut))
        try await clock.waitForSleepers()
        clock.advance(by: debounce)
        try await taskProvider.waitForAllTasks()
    }

    private func scroll(_ sut: SUT, toVisibleTop y: CGFloat) {
        sut.list.contentView.scroll(to: NSPoint(x: 0, y: y))
        sut.list.reflectScrolledClipView(sut.list.contentView)
    }

    private func panelOrigin(_ sut: SUT) throws -> NSPoint {
        try #require(sut.window.childWindows?.first).frame.origin
    }

    @Test
    func `scrolling the card list moves the panel with its identifier`() async throws {
        let sut = try makeSUT()
        try await showPanel(row: 10, in: sut)
        let before = try panelOrigin(sut)

        scroll(sut, toVisibleTop: 20)

        #expect(sut.controller.isPanelVisible)
        #expect(try panelOrigin(sut) == NSPoint(x: before.x, y: before.y + 20))
    }

    @Test
    func `scrolling the identifier out of the card list closes the panel`() async throws {
        let sut = try makeSUT()
        try await showPanel(row: 10, in: sut)

        scroll(sut, toVisibleTop: 1500)

        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `an identifier the card's pinned header covers closes the panel`() async throws {
        let sut = try makeSUT()
        try await showPanel(row: 0, in: sut)

        // The header pins at the list's top edge, and from this top on it covers row 0, still inside the list.
        scroll(sut, toVisibleTop: cardTop + DiffPaneMetrics.containerInset + sut.rendered.lineHeight + 1)

        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `scrolling the card list before the panel shows cancels the hover`() async throws {
        let sut = try makeSUT()
        sut.controller.pointerMoved(to: point(row: 10, in: sut))

        scroll(sut, toVisibleTop: 20)
        try await taskProvider.waitForAllTasks()

        #expect(!sut.controller.isPanelVisible)
    }
}

/// The panel follows its identifier while any of it shows and closes once none does; an identifier that cannot be
/// measured leaves the panel where it is.
struct HoverScrollResponseTests {
    private let visible = NSRect(x: 0, y: 100, width: 400, height: 300)

    @Test
    func `an identifier still in view is followed to its new rect`() {
        let anchor = NSRect(x: 40, y: 120, width: 60, height: 14)
        #expect(HoverScrollResponse(anchorRect: anchor, visibleRect: visible) == .follow(anchor))
    }

    @Test
    func `an identifier partly in view is still followed`() {
        let anchor = NSRect(x: 40, y: 94, width: 60, height: 14)
        #expect(HoverScrollResponse(anchorRect: anchor, visibleRect: visible) == .follow(anchor))
    }

    @Test
    func `an identifier out of view closes the panel`() {
        let anchor = NSRect(x: 40, y: 80, width: 60, height: 14)
        #expect(HoverScrollResponse(anchorRect: anchor, visibleRect: visible) == .close)
    }

    @Test
    func `an identifier touching the view's edge from outside closes the panel`() {
        let anchor = NSRect(x: 40, y: 86, width: 60, height: 14)
        #expect(HoverScrollResponse(anchorRect: anchor, visibleRect: visible) == .close)
    }

    @Test
    func `an identifier that cannot be measured leaves the panel where it is`() {
        #expect(HoverScrollResponse(anchorRect: nil, visibleRect: visible) == .stay)
    }
}
