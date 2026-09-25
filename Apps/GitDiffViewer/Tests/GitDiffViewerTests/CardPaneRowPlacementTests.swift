import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A card pane that never wraps shows each row where the card measured it, however far into the card the list is
/// scrolled when its text changes (book DIFF-06, CARD-17). TextKit lays out only what shows; a row it lays out below
/// rows it has not laid out goes where it estimates those rows end, and it estimates a long line as two.
@MainActor
@Suite(.mainActorLane)
struct CardPaneRowPlacementTests {
    /// `count` lines; every seventh is long enough that TextKit, estimating it before laying it out, takes it for
    /// two lines.
    private static func lines(_ count: Int) -> [String] {
        let tail = String(repeating: "long ", count: 32)
        return (1 ... count).map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" }
    }

    /// Six hundred lines changed every forty, three lines of context around each change, `expansions` revealed.
    private static func changes(revealing expansions: [GapKey: GapExpansion] = [:]) -> RenderedDiff {
        let old = lines(600)
        var new = old
        for line in stride(from: 20, to: 600, by: 40) { new[line] = "let value\(line + 1) = changed" }
        let prepared = PreparedDiff(
            FileDiffInput(
                title: "", oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
                language: .plain), granularity: .word)
        return DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified]),
            layout: .changes(context: 3, expansions: expansions), withHeaders: false)
    }

    private static func file(lines count: Int) -> RenderedDiff {
        let text = lines(count).joined(separator: "\n") + "\n"
        return DiffRenderer.render(oldText: text, newText: text, language: .plain)
    }

    @Test
    func `after a reveal deep in a card, line numbers and the separator sit on the rows the card measured`() throws {
        let before = Self.changes()
        let sut = CardInList(showing: before)
        sut.scroll(toCardY: 1_200)
        let text = try #require(before.unified)
        let visible = try #require(sut.textView).visibleRect
        let measuredBefore = MeasuredRows(text)
        // A gap between two changes whose band shows, clear of the list's edges.
        let gap = try #require(
            text.gaps.first { gap in
                let top = measuredBefore.top(ofRow: gap.boundary) + sut.inset
                return gap.hasSeparator && top > visible.minY + 60 && top < visible.maxY - 60
            })

        let after = Self.changes(revealing: [gap.marker.key: GapExpansion(below: 3, above: 2)])
        sut.show(after)

        let revealed = try #require(after.unified)
        let measured = MeasuredRows(revealed)
        // Read first: asking the gutter lays rows out, which moves the ones TextKit placed from its estimates.
        let shown = sut.shownRows()
        try #require(shown.count > 10)
        for (row, y) in shown {
            #expect(abs(y - (measured.top(ofRow: row) + sut.inset)) < 0.5, "row \(row) where the card measured it")
        }
        let numbers = sut.gutterRows()
        for (row, y) in shown {
            #expect(abs((numbers[row] ?? .nan) - y) < 0.5, "line number of row \(row) on its row")
        }
        let boundary = try #require(revealed.gaps.first { $0.marker.key == gap.marker.key }).boundary
        let rowBelow = try #require(shown[boundary])
        let band = try #require(sut.gutterBands()[gap.marker.key])
        let separator = band.minY + GapHandleLayout.separatorOffset(bandHeight: band.height)
        #expect(separator >= rowBelow - revealed.gapBandHeight && separator < rowBelow)
    }

    /// TextKit drops the layout of the rows a pass no longer shows; laid out again from what shows, rows above it sat
    /// a wrapped row's extra lines away from where the card measured them.
    @Test
    func `a wrapped card scrolled deep and back shows each row where the card measured it`() throws {
        let rendered = Self.file(lines: 300)
        let sut = CardInList(showing: rendered, wrapMode: .viewport)
        let text = try #require(rendered.unified)
        let measured = MeasuredRows(text, wrapWidth: sut.wrapWidth)

        for y in [3_000, 3_200, 3_400, 3_200, 3_000] {
            sut.scroll(toCardY: CGFloat(y))
            let shown = sut.shownRows()
            try #require(shown.count > 10, "rows show at \(y)")
            for (row, top) in shown {
                #expect(abs(top - (measured.top(ofRow: row) + sut.inset)) < 0.5, "row \(row) at \(y)")
            }
        }
    }

    /// A card lays its text out from its top, so rows TextKit drops above what shows are typeset again on the next
    /// scroll step, from the top. The card's layout manager declines the message TextKit drops them with, and the card
    /// places its container itself only while TextKit still sends it: a later TextKit that renames it fails here.
    @Test
    func `a card's layout manager declines to drop the rows it laid out`() throws {
        let sut = CardInList(showing: Self.file(lines: 40))
        let flush = NSSelectorFromString("flushTextLayoutFragmentsFromLocation:direction:")

        let layoutManager = try #require(sut.textView?.textLayoutManager)

        #expect(NSTextLayoutManager.instancesRespond(to: flush))
        #expect(layoutManager is RetainingTextLayoutManager)
        #expect(!layoutManager.responds(to: flush))
        #expect((sut.textView as? DiffPaneTextView)?.placesContainerAtInset == true)
    }

    /// AppKit works out a text view's container origin from its whole laid-out text when the container keeps its own
    /// width, as a wrapped card's does, and reads it on every pass.
    @Test
    func `a wrapped card showing its top lays out only the rows near its top`() {
        let sut = CardInList(showing: Self.file(lines: 300), wrapMode: .viewport)

        let laidOut = sut.fragments()

        #expect(!laidOut.isEmpty)
        #expect(laidOut.count < 100, "\(laidOut.count) rows of 300 laid out")
    }

    @Test
    func `a card that grows while scrolled deep still shows its last line at its end`() throws {
        let sut = CardInList(showing: Self.file(lines: 400))
        sut.scroll(toCardY: 3_000)

        let grown = Self.file(lines: 600)
        sut.show(grown)
        sut.scrollToEnd()

        let text = try #require(grown.unified)
        let last = text.rows.count - 1
        let lastTop = try #require(sut.shownRows()[last])
        #expect(abs(lastTop - (MeasuredRows(text).top(ofRow: last) + sut.inset)) < 0.5)
        #expect(lastTop + text.lineHeight <= sut.cardHeight)
    }
}

/// Where a fully laid-out text puts each row: the tops a card's height counts on.
@MainActor
struct MeasuredRows {
    private let tops: [Int: CGFloat]

    /// - Parameters:
    ///   - rendered: The card's text.
    ///   - wrapWidth: The width the card wraps at, or nil for a card that never wraps.
    init(_ rendered: RenderedText, wrapWidth: CGFloat? = nil) {
        let layout = StaticTextLayout(rendered: rendered)
        if let wrapWidth {
            layout.layOut(mode: .viewport, viewportWidth: wrapWidth)
        } else {
            // A column no row reaches lays the whole text out, one line per row, as the card measures it.
            layout.layOut(mode: .column(100_000), viewportWidth: 600)
        }
        let layoutManager = layout.layoutManager
        var tops: [Int: CGFloat] = [:]
        let start = layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let content = layoutManager.textContentManager else { return false }
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            tops[rendered.rowIndex(containing: offset)] = fragment.layoutFragmentFrame.minY
            return true
        }
        self.tops = tops
    }

    func top(ofRow row: Int) -> CGFloat {
        tops[row] ?? .nan
    }
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

/// A card pane that never wraps, in a list that shows part of it, as the card list hosts one: measured by its
/// hosting controller's `sizeThatFits`, placed in the list's document, in a window that is never ordered in.
@MainActor
private final class CardInList {
    private static let width: CGFloat = 600
    /// Where the card starts in the list's document.
    private static let cardTop: CGFloat = 40

    private let window: NSWindow
    private let list: NSScrollView
    private let document = FlippedDocument()
    private let body: NSHostingController<EmbeddedDiffTextView>
    private let wrapMode: WrapMode

    init(showing rendered: RenderedDiff, wrapMode: WrapMode = .none) {
        self.wrapMode = wrapMode
        body = NSHostingController(rootView: Self.pane(rendered, wrapMode: wrapMode))
        body.sizingOptions = []
        body.safeAreaRegions = []
        list = NSScrollView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 300))
        list.hasVerticalScroller = true
        list.automaticallyAdjustsContentInsets = false
        list.documentView = document
        document.addSubview(body.view)
        window = NSWindow(
            contentRect: list.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = list
        place()
    }

    private static func pane(_ rendered: RenderedDiff, wrapMode: WrapMode) -> EmbeddedDiffTextView {
        EmbeddedDiffTextView(
            layouts: CardLayouts(rendered: rendered), side: .unified, gutter: .dual, width: width, wrapMode: wrapMode)
    }

    var textView: NSTextView? { Self.first(NSTextView.self, in: body.view) }
    private var gutter: DiffGutterView? { Self.first(DiffGutterView.self, in: body.view) }
    var cardHeight: CGFloat { body.view.frame.height }
    /// The space above the card's first row.
    var inset: CGFloat { textView?.textContainerInset.height ?? .nan }
    /// The card's y at the list's top edge.
    var visibleCardTop: CGFloat { list.contentView.bounds.minY - Self.cardTop }

    /// Shows a new render of the card, as the list does when a reveal or a reload renders it again.
    func show(_ rendered: RenderedDiff) {
        body.rootView = Self.pane(rendered, wrapMode: wrapMode)
        place()
    }

    func scroll(toCardY y: CGFloat) {
        list.contentView.scroll(to: NSPoint(x: 0, y: Self.cardTop + y))
        list.reflectScrolledClipView(list.contentView)
        settle()
    }

    func scrollToEnd() {
        list.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - list.contentView.bounds.height))
        list.reflectScrolledClipView(list.contentView)
        settle()
    }

    /// The rows TextKit has laid out in what shows of the card, each with its top in the card, read without laying
    /// anything out: where the card's text shows them.
    func shownRows() -> [Int: CGFloat] {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let content = layoutManager.textContentManager, let rendered = gutter?.rendered
        else { return [:] }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin.y
        let start = layoutManager.documentRange.location
        var rows: [Int: CGFloat] = [:]
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: origin)
            guard fragment.state == .layoutAvailable, frame.maxY > visible.minY, frame.minY < visible.maxY else {
                return true
            }
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            rows[rendered.rowIndex(containing: offset)] = frame.minY
            return true
        }
        return rows
    }

    /// The fragment of each row the card's text view holds laid out, shown or not, read without laying anything out.
    func fragments() -> [Int: NSTextLayoutFragment] {
        guard let layoutManager = textView?.textLayoutManager, let content = layoutManager.textContentManager,
            let rendered = gutter?.rendered
        else { return [:] }
        let start = layoutManager.documentRange.location
        var fragments: [Int: NSTextLayoutFragment] = [:]
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            guard fragment.state == .layoutAvailable else { return true }
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            fragments[rendered.rowIndex(containing: offset)] = fragment
            return true
        }
        return fragments
    }

    /// The width the card's text wraps at.
    var wrapWidth: CGFloat { textView?.textContainer?.size.width ?? .nan }

    /// The y the gutter gives each row's line number that shows, in the card.
    func gutterRows() -> [Int: CGFloat] {
        guard let gutter, let textView else { return [:] }
        var rows: [Int: CGFloat] = [:]
        gutter.forEachFragment(in: gutter.convert(textView.visibleRect, from: textView)) { _, _, row, y in
            rows[row] = y
        }
        return rows
    }

    /// The band the gutter gives each gap that shows, in the card.
    func gutterBands() -> [GapKey: NSRect] {
        guard let gutter, let textView else { return [:] }
        var bands: [GapKey: NSRect] = [:]
        gutter.forEachGap(in: gutter.convert(textView.visibleRect, from: textView)) { gap, band in
            bands[gap.marker.key] = band
        }
        return bands
    }

    /// Measures the card as the list does, places it, and lets the change reach the screen.
    private func place() {
        let height = body.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
        document.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.cardTop + height + Self.cardTop)
        body.view.frame = NSRect(x: 0, y: Self.cardTop, width: Self.width, height: height)
        settle()
    }

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events.
    private func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}
