import AppKit
import DiffCore
import Metal
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A wrapped card lays its text out, fully, as soon as it is measured (``StaticTextLayout/sharesLayout``), which
/// always comes before its colour: the pipeline colours a text off the main actor, so a card always shows first with
/// none. Once colour lands as a second, separate update, as it does for a card already on screen, every row the
/// measure laid out eagerly must still take it, not only the rows a first layout would have reached.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct CardLateColourTests {
    private static let count = 400
    private static let text = (1 ... count).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"

    /// A card discarded and rebuilt keeps the colour its content already had: unmounting a card's body, as scrolling
    /// it off screen does, discards its text view and coordinator; a card whose file is still shown, scrolled back,
    /// must show that colour again in a fresh text view, without a second colouring job.
    @Test
    func `a card rebuilt after being scrolled off keeps the colour its file already had`() async throws {
        let rendered = DiffRenderer.render(oldText: Self.text, newText: Self.text, language: .swift)
        let decorations = DecorationFixtures.colors(
            old: await DecorationFixtures.lexed(Self.text, language: .swift),
            new: await DecorationFixtures.lexed(Self.text, language: .swift))
        let layouts = CardLayouts(rendered: rendered)
        let card = RemountingCard(layouts: layouts, decorations: decorations)
        try #require(card.uncolouredLaidOutRows().isEmpty, "the first mount should colour every row")

        card.unmount()
        card.remount()

        let plain = card.uncolouredLaidOutRows()
        #expect(plain.isEmpty, "rows plain after remounting: \(plain.prefix(6))")
    }

    @Test
    func `colour that lands after a wrapped card is already laid out still reaches every row`() async throws {
        let rendered = DiffRenderer.render(oldText: Self.text, newText: Self.text, language: .swift)
        let card = LateColourCard(showing: rendered)
        let before = try card.pixels()

        // Laid out already, its rows are the measure's; colouring it now must still validate every one of them.
        #expect(card.laidOutRows > 100, "only \(card.laidOutRows) rows laid out before colour landed")
        card.update(
            decorations: DecorationFixtures.colors(
                old: await DecorationFixtures.lexed(Self.text, language: .swift),
                new: await DecorationFixtures.lexed(Self.text, language: .swift)))

        let after = try card.pixels()
        #expect(after.differing(from: before, in: card.bounds) > 0, "no row changed once colour landed")
        let plain = card.uncolouredLaidOutRows()
        #expect(plain.isEmpty, "rows the measure laid out first that stayed plain: \(plain.prefix(6))")
    }
}

/// A card that wraps, hosted as the card list hosts one, in a window that is never ordered in; measured, and so fully
/// laid out, before it ever gets ``update(decorations:)``.
@MainActor
private final class LateColourCard {
    private static let width: CGFloat = 600
    private let window: NSWindow
    private let body: NSHostingController<EmbeddedDiffTextView>
    private let layouts: CardLayouts

    init(showing rendered: RenderedDiff) {
        layouts = CardLayouts(rendered: rendered)
        body = NSHostingController(rootView: Self.pane(layouts, decorations: nil))
        body.sizingOptions = []
        body.safeAreaRegions = []
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = body.view
        place()
    }

    private static func pane(_ layouts: CardLayouts, decorations: DiffDecorations?) -> EmbeddedDiffTextView {
        EmbeddedDiffTextView(
            layouts: layouts, side: .unified, gutter: .dual, width: width, wrapMode: .viewport
        )
        .decorated(with: decorations)
    }

    var bounds: NSRect { window.contentView?.bounds ?? .zero }

    /// How many rows the text view's layout manager holds laid out, before or after colouring.
    var laidOutRows: Int {
        guard let textView = firstSubview(NSTextView.self, in: body.view),
            let layoutManager = textView.textLayoutManager
        else { return 0 }
        var count = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            if fragment.state == .layoutAvailable { count += 1 }
            return true
        }
        return count
    }

    /// Hands the pane new decorations as SwiftUI does, then lets the change reach the screen.
    func update(decorations: DiffDecorations?) {
        body.rootView = Self.pane(layouts, decorations: decorations)
        settle()
    }

    /// Every row TextKit had already laid out that carries no foreground colour.
    func uncolouredLaidOutRows() -> [Int] {
        guard let textView = firstSubview(NSTextView.self, in: body.view),
            let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager,
            let rendered = layouts.unified?.rendered
        else { return [] }
        let start = layoutManager.documentRange.location
        var coloured: [Range<Int>] = []
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if attributes[.foregroundColor] != nil {
                let lower = content.offset(from: start, to: range.location)
                coloured.append(lower ..< lower + content.offset(from: range.location, to: range.endLocation))
            }
            return true
        }
        var plain: [Int] = []
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            guard fragment.state == .layoutAvailable else { return true }
            let row = rendered.rowIndex(
                containing: content.offset(from: start, to: fragment.rangeInElement.location))
            let lineStart = rendered.lineStarts[row]
            let end = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] : Int.max
            if !coloured.contains(where: { $0.overlaps(lineStart ..< end) }) { plain.append(row) }
            return true
        }
        return plain
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(window.contentView?.layer))
    }

    /// Measures the card as the list does, sizes and places it, and lets the change reach the screen.
    private func place() {
        let height = body.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
        body.view.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        settle()
    }

    private func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}

/// One card's body, mounted or not, as ``CardBodyMount`` does for the real card list: unmounting removes the
/// ``EmbeddedDiffTextView`` from the hierarchy, dismantling its text view and coordinator; mounting builds it again.
private struct MountedCard: View {
    let layouts: CardLayouts?
    let decorations: DiffDecorations?
    static let width: CGFloat = 600

    var body: some View {
        if let layouts {
            EmbeddedDiffTextView(
                layouts: layouts, side: .unified, gutter: .dual, width: Self.width, wrapMode: .viewport
            )
            .decorated(with: decorations)
        }
    }
}

/// A card hosted as the list hosts one, whose body can be unmounted and remounted with the same measuring layouts, as
/// scrolling a card off screen and back does.
@MainActor
private final class RemountingCard {
    private let window: NSWindow
    private let body: NSHostingController<MountedCard>
    private let layouts: CardLayouts
    private let decorations: DiffDecorations?

    init(layouts: CardLayouts, decorations: DiffDecorations?) {
        self.layouts = layouts
        self.decorations = decorations
        body = NSHostingController(rootView: MountedCard(layouts: layouts, decorations: decorations))
        body.sizingOptions = []
        body.safeAreaRegions = []
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: MountedCard.width, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = body.view
        place()
    }

    /// Removes the text view from the hierarchy, as a card scrolled off screen does.
    func unmount() {
        body.rootView = MountedCard(layouts: nil, decorations: nil)
        settle()
    }

    /// Builds the text view again, over the same measuring layouts, as a card scrolled back does.
    func remount() {
        body.rootView = MountedCard(layouts: layouts, decorations: decorations)
        place()
    }

    /// Every row TextKit had already laid out that carries no foreground colour.
    func uncolouredLaidOutRows() -> [Int] {
        guard let textView = firstSubview(NSTextView.self, in: body.view),
            let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager,
            let rendered = layouts.unified?.rendered
        else { return [] }
        let start = layoutManager.documentRange.location
        var coloured: [Range<Int>] = []
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if attributes[.foregroundColor] != nil {
                let lower = content.offset(from: start, to: range.location)
                coloured.append(lower ..< lower + content.offset(from: range.location, to: range.endLocation))
            }
            return true
        }
        var plain: [Int] = []
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            guard fragment.state == .layoutAvailable else { return true }
            let row = rendered.rowIndex(
                containing: content.offset(from: start, to: fragment.rangeInElement.location))
            let lineStart = rendered.lineStarts[row]
            let end = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] : Int.max
            if !coloured.contains(where: { $0.overlaps(lineStart ..< end) }) { plain.append(row) }
            return true
        }
        return plain
    }

    private func place() {
        let height = body.sizeThatFits(in: CGSize(width: MountedCard.width, height: .greatestFiniteMagnitude)).height
        body.view.frame = NSRect(x: 0, y: 0, width: MountedCard.width, height: height)
        settle()
    }

    private func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}
