import AppKit
import DiffCore
import Metal
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A wrapped card measures its height by laying out every row, before its text view shows any, and the view shows
/// those rows as they were laid out (``StaticTextLayout/sharesLayout``). TextKit validates a fragment's colour as it
/// lays it out, and the card's decoration store was not on the layout manager then: the rows it shows deep in a long
/// file must still carry their syntax colour, pixel for pixel as a card whose view laid its rows out itself draws
/// them, before a reveal and after it renders the card anew.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct CardSharedLayoutColourTests {
    private static let count = 600
    private static let tail = String(repeating: "long ", count: 32)
    private static let old = (1 ... count)
        .map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" }
    private static let new = old.enumerated()
        .map { $0.offset % 40 == 20 ? "let value\($0.offset + 1) = changed" : $0.element }

    /// The file's changes with twelve lines around each, `expansions` revealed.
    private static func diff(revealing expansions: [GapKey: GapExpansion] = [:]) -> RenderedDiff {
        let prepared = PreparedDiff(
            FileDiffInput(
                title: "a.swift", oldText: old.joined(separator: "\n") + "\n",
                newText: new.joined(separator: "\n") + "\n", language: .swift),
            granularity: .word)
        return DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified]),
            layout: .changes(context: 12, expansions: expansions), withHeaders: false)
    }

    @Test
    func `a wrapped card deep in a long file shows its measured rows in syntax colour, and after a reveal`()
        async throws
    {
        let decorations = DecorationFixtures.colors(
            old: await DecorationFixtures.lexed(Self.old.joined(separator: "\n") + "\n", language: .swift),
            new: await DecorationFixtures.lexed(Self.new.joined(separator: "\n") + "\n", language: .swift))
        let before = Self.diff()
        let shared = DecoratedCardInList(showing: before, decorations: decorations, sharesLayout: true)
        let own = DecoratedCardInList(showing: before, decorations: decorations, sharesLayout: false)
        let plain = DecoratedCardInList(showing: before, decorations: nil, sharesLayout: true)
        let deep = shared.cardHeight * 0.7
        for card in [shared, own, plain] { card.scroll(toCardY: deep) }
        try Self.expectColoured(shared, like: own, unlike: plain, "before a reveal")

        let text = try #require(before.unified)
        let shown = shared.shownRows()
        let gap = try #require(text.gaps.first { shown.contains($0.boundary) }, "no gap shows")
        let after = Self.diff(revealing: [gap.marker.key: GapExpansion(below: 3, above: 2)])
        for card in [shared, own, plain] { card.show(after) }

        try Self.expectColoured(shared, like: own, unlike: plain, "after a reveal")
    }

    /// Expects `shared` to show rows its measure laid out, drawn byte for byte as `own` draws them, and in colour:
    /// unlike `plain`, which shows the same rows undecorated.
    private static func expectColoured(
        _ shared: DecoratedCardInList, like own: DecoratedCardInList, unlike plain: DecoratedCardInList,
        _ moment: String
    ) throws {
        let layout = try #require(shared.layouts.unified)
        #expect(shared.textView?.textLayoutManager === layout.layoutManager, "\(moment): the view's own layout")
        #expect(shared.laidOutRows == layout.rendered.rows.count, "\(moment): rows the measure did not lay out")
        #expect(shared.shownRows().count > 5, "\(moment): too few rows show")
        let pixels = try shared.pixels()
        #expect(pixels.differing(from: try own.pixels(), in: shared.bounds) == 0, "\(moment): drawn otherwise")
        #expect(pixels.differing(from: try plain.pixels(), in: shared.bounds) > 0, "\(moment): drawn plain")
    }
}

/// A decorated card that wraps, in a list that shows part of it, as the card list hosts one, in a window that is never
/// ordered in; its text view shows its measuring layout, or lays its text out itself, as `sharesLayout` says.
@MainActor
private final class DecoratedCardInList {
    private static let width: CGFloat = 600
    /// Where the card starts in the list's document.
    private static let cardTop: CGFloat = 40

    private let window: NSWindow
    private let list: NSScrollView
    private let document = FlippedCardDocument()
    private let body: NSHostingController<EmbeddedDiffTextView>
    private let decorations: DiffDecorations?
    private let sharesLayout: Bool

    init(showing rendered: RenderedDiff, decorations: DiffDecorations?, sharesLayout: Bool) {
        self.decorations = decorations
        self.sharesLayout = sharesLayout
        body = NSHostingController(
            rootView: Self.pane(rendered, decorations: decorations, sharesLayout: sharesLayout))
        body.sizingOptions = []
        body.safeAreaRegions = []
        list = NSScrollView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 300))
        list.hasVerticalScroller = false
        list.automaticallyAdjustsContentInsets = false
        list.documentView = document
        document.addSubview(body.view)
        window = NSWindow(contentRect: list.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = list
        list.wantsLayer = true
        place()
    }

    /// The card's pane, its layouts made with the text view showing them or laying them out itself.
    private static func pane(_ rendered: RenderedDiff, decorations: DiffDecorations?, sharesLayout: Bool)
        -> EmbeddedDiffTextView
    {
        StaticTextLayout.sharesLayoutWithView = sharesLayout
        defer { StaticTextLayout.sharesLayoutWithView = true }
        return EmbeddedDiffTextView(
            layouts: CardLayouts(rendered: rendered), side: .unified, gutter: .dual, width: width,
            wrapMode: .viewport
        )
        .decorated(with: decorations)
    }

    var layouts: CardLayouts { body.rootView.layouts }
    var textView: NSTextView? { firstSubview(NSTextView.self, in: body.view) }
    var cardHeight: CGFloat { body.view.frame.height }
    var bounds: NSRect { list.bounds }

    /// How many rows the text view's layout manager holds laid out.
    var laidOutRows: Int {
        guard let layoutManager = textView?.textLayoutManager else { return 0 }
        var count = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            if fragment.state == .layoutAvailable { count += 1 }
            return true
        }
        return count
    }

    /// Shows a new render of the card, as the list does when a reveal renders it again.
    func show(_ rendered: RenderedDiff) {
        body.rootView = Self.pane(rendered, decorations: decorations, sharesLayout: sharesLayout)
        place()
    }

    func scroll(toCardY y: CGFloat) {
        list.contentView.scroll(to: NSPoint(x: 0, y: Self.cardTop + y))
        list.reflectScrolledClipView(list.contentView)
        settle()
    }

    /// The rows laid out in what shows of the card, read without laying anything out.
    func shownRows() -> Set<Int> {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let content = layoutManager.textContentManager, let rendered = layouts.unified?.rendered
        else { return [] }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin.y
        let start = layoutManager.documentRange.location
        var rows: Set<Int> = []
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: origin)
            if fragment.state == .layoutAvailable, frame.maxY > visible.minY, frame.minY < visible.maxY {
                let offset = content.offset(from: start, to: fragment.rangeInElement.location)
                rows.insert(rendered.rowIndex(containing: offset))
            }
            return frame.minY < visible.maxY
        }
        return rows
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(window.contentView?.layer))
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
}

private final class FlippedCardDocument: NSView {
    override var isFlipped: Bool { true }
}
