import AppKit
import DiffComparison
import DiffCore
import Metal
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// After a gap handle reveals lines, and after the file then updates, each line number sits on its text row, the
/// separator between two handles runs level with its gap's band in the text, and nothing drawn before is left behind
/// (book DIFF-06). Checked in each layout of the single-file view, unwrapped and wrapped, and of the card list.
///
/// What shows is read from what the layers hold (``LayerPixels/composite(_:)``) and compared, by bytes, with what the
/// same views draw when every one of them is asked to draw again: a view that kept an earlier drawing differs.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct FilePaneRevealAlignmentTests {
    @Test(arguments: PaneLayout.allCases)
    func `after a reveal, a file pane's numbers, separator and drawing follow the revealed rows`(
        layout: PaneLayout
    ) async throws {
        try await RevealAlignment.revealInFilePanes(layout: layout, wrapsLines: false)
    }
}

/// ``FilePaneRevealAlignmentTests`` after the file updates, once lines were revealed. Each suite here checks one change
/// in one kind of pane, so that each keeps within the main thread's budget.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct FilePaneUpdateAlignmentTests {
    @Test(arguments: PaneLayout.allCases)
    func `after the file updates, a revealed file pane's numbers, separator and drawing follow its rows`(
        layout: PaneLayout
    ) async throws {
        try await RevealAlignment.updateInFilePanes(layout: layout, wrapsLines: false)
    }
}

/// ``FilePaneRevealAlignmentTests`` with lines wrapped, where the split view aligns the two sides' rows once it has
/// shown them.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct WrappedFilePaneRevealAlignmentTests {
    @Test(arguments: PaneLayout.allCases)
    func `after a reveal, a wrapped file pane's numbers, separator and drawing follow the revealed rows`(
        layout: PaneLayout
    ) async throws {
        try await RevealAlignment.revealInFilePanes(layout: layout, wrapsLines: true)
    }
}

/// ``FilePaneUpdateAlignmentTests`` with lines wrapped.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct WrappedFilePaneUpdateAlignmentTests {
    @Test(arguments: PaneLayout.allCases)
    func `after the file updates, a revealed wrapped file pane's numbers, separator and drawing follow its rows`(
        layout: PaneLayout
    ) async throws {
        try await RevealAlignment.updateInFilePanes(layout: layout, wrapsLines: true)
    }
}

/// ``FilePaneRevealAlignmentTests`` in a card of the card list, inline or side by side, which the stacked layout shows
/// too; a card's rows also sit where the card measured them, as a full layout of its text puts them.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct CardPaneRevealAlignmentTests {
    @Test(arguments: [CardLayout.inline, .split], [false, true])
    func `after a reveal, a card's numbers, separator and drawing follow the revealed rows`(
        layout: CardLayout, wrapsLines: Bool
    ) throws {
        let sut = HostedCardBody(showing: RevealFixture.diff(), layout: layout, wrapsLines: wrapsLines)

        sut.show(try RevealFixture.revealed())

        try RevealAlignment.expectAligned(sut.panes(), measuredBy: sut.measuredTops)
        #expect(try sut.pixels().differing(from: try sut.redrawnPixels(), in: sut.bounds) == 0, "nothing stale")
    }
}

/// ``CardPaneRevealAlignmentTests`` after the file updates, once lines were revealed.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct CardPaneUpdateAlignmentTests {
    @Test(arguments: [CardLayout.inline, .split], [false, true])
    func `after the file updates, a revealed card's numbers, separator and drawing follow its rows`(
        layout: CardLayout, wrapsLines: Bool
    ) throws {
        let sut = HostedCardBody(showing: try RevealFixture.revealed(), layout: layout, wrapsLines: wrapsLines)

        sut.show(try RevealFixture.revealed(updated: true))

        try RevealAlignment.expectAligned(sut.panes(), measuredBy: sut.measuredTops)
        #expect(try sut.pixels().differing(from: try sut.redrawnPixels(), in: sut.bounds) == 0, "nothing stale")
    }
}

/// A file of forty lines changed at lines 8 and 30, shown with two lines of context around each change: a gap above
/// the first change, one between the two, which offers two handles, and one below the last. Line 30 is long on the
/// new side, so that it wraps where the pane wraps and the split view aligns the other side's row to it.
@MainActor
enum RevealFixture {
    private static let longTail = String(repeating: " + value", count: 16)

    /// The two sides; `updated` is the file after it changed on disk, with line 8 changed again and a line added
    /// after it, so every row below moves and takes another number.
    private static func sides(updated: Bool) -> (old: String, new: String) {
        let old = (1 ... 40).map { "let value\($0) = \($0)" }
        var new = old
        new[7] = updated ? "let value8 = eight" : "let value8 = 8 * 1"
        new[29] = "let value30 = 30" + longTail
        if updated { new.insert("let value8b = 8", at: 8) }
        return (old.joined(separator: "\n") + "\n", new.joined(separator: "\n") + "\n")
    }

    static func diff(revealing expansions: [GapKey: GapExpansion] = [:], updated: Bool = false) -> RenderedDiff {
        let sides = sides(updated: updated)
        return DiffRenderer.render(
            oldText: sides.old, newText: sides.new, language: .plain,
            layout: .changes(context: 2, expansions: expansions))
    }

    /// The gap between the two changes.
    static func middleGap() throws -> GapKey {
        let gaps = try #require(diff().new).gaps
        return try #require(gaps.first { $0.hasSeparator }).marker.key
    }

    /// The file with three lines revealed below the first change and two above the second, as dragging each of the
    /// middle gap's handles reveals them.
    static func revealed(updated: Bool = false) throws -> RenderedDiff {
        diff(revealing: [try middleGap(): GapExpansion(below: 3, above: 2)], updated: updated)
    }
}

/// One pane as it shows: its gutter, its text view and the text they show.
@MainActor
struct AlignedPane {
    let gutter: DiffGutterView
    let textView: NSTextView
    let rendered: RenderedText

    /// A row's first line as the text view laid it out: its frame and its baseline in window coordinates, and the
    /// row's top in the text container.
    struct Line {
        let frame: NSRect
        let baseline: CGFloat
        let top: CGFloat
    }

    /// The rows whose first line the text view has laid out wholly within what shows, read without laying anything
    /// out: where the text shows them.
    func shownLines() -> [Int: Line] {
        guard let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager else {
            return [:]
        }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let start = layoutManager.documentRange.location
        var lines: [Int: Line] = [:]
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            guard fragment.state == .layoutAvailable, let first = fragment.textLineFragments.first else { return true }
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            let bounds = first.typographicBounds
            let line = NSRect(
                x: frame.minX, y: frame.minY + bounds.minY, width: max(bounds.width, 1), height: bounds.height)
            guard visible.minY <= line.minY, line.maxY <= visible.maxY else { return true }
            let baseline = frame.minY + bounds.minY + first.glyphOrigin.y - rendered.baselineOffset
            let row = rendered.rowIndex(containing: content.offset(from: start, to: fragment.rangeInElement.location))
            lines[row] = Line(
                frame: textView.convert(line, to: nil),
                baseline: textView.convert(NSPoint(x: 0, y: baseline), to: nil).y,
                top: fragment.layoutFragmentFrame.minY)
            return true
        }
        return lines
    }

    /// Where the text draws the separator across the band after `row`, in window coordinates: the middle of its
    /// one-point line. Nil unless the row is laid out and a band follows it.
    func textSeparator(afterRow row: Int) -> CGFloat? {
        guard let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager,
            let location = content.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]),
            let fragment = layoutManager.textLayoutFragment(for: location), fragment.state == .layoutAvailable
        else { return nil }
        let band = rendered.gapBandHeight
        let y =
            textView.textContainerOrigin.y + fragment.layoutFragmentFrame.maxY - band
            + GapHandleLayout.separatorOffset(bandHeight: band) + 0.5
        return textView.convert(NSPoint(x: 0, y: y), to: nil).y
    }

    /// Where the gutter draws the separator of each gap in what shows, in window coordinates.
    func gutterSeparators() -> [GapKey: CGFloat] {
        var separators: [GapKey: CGFloat] = [:]
        gutter.forEachGap(in: gutter.visibleRect) { gap, band in
            let y = band.minY + GapHandleLayout.separatorOffset(bandHeight: band.height) + 0.5
            separators[gap.marker.key] = gutter.convert(NSPoint(x: 0, y: y), to: nil).y
        }
        return separators
    }
}

@MainActor
enum RevealAlignment {
    /// The file panes' window: the fixture's rows around its middle gap show whole in each layout, and each frame read
    /// costs as few pixels as that allows.
    static let paneSize = NSSize(width: 600, height: 400)

    /// Shows the fixture in file panes of `layout`, reveals lines in its middle gap, and checks what shows.
    static func revealInFilePanes(layout: PaneLayout, wrapsLines: Bool) async throws {
        let sut = HostedPanes(
            showing: PaneText(rendered: RevealFixture.diff(), asksForChange: false), layout: layout,
            wrapsLines: wrapsLines, size: RevealAlignment.paneSize)
        try await sut.alignSides()

        sut.show(PaneText(rendered: try RevealFixture.revealed(), asksForChange: false))
        try await sut.alignSides()

        try expectAligned(sut.shownPanes())
        #expect(try sut.pixels().differing(from: try sut.redrawnPixels(), in: sut.bounds) == 0, "nothing stale")
    }

    /// Shows the fixture with lines revealed in file panes of `layout`, updates the file, and checks what shows.
    static func updateInFilePanes(layout: PaneLayout, wrapsLines: Bool) async throws {
        let sut = HostedPanes(
            showing: PaneText(rendered: try RevealFixture.revealed(), asksForChange: false), layout: layout,
            wrapsLines: wrapsLines, size: RevealAlignment.paneSize)
        try await sut.alignSides()

        sut.show(PaneText(rendered: try RevealFixture.revealed(updated: true), asksForChange: false))
        try await sut.alignSides()

        try expectAligned(sut.shownPanes())
        #expect(try sut.pixels().differing(from: try sut.redrawnPixels(), in: sut.bounds) == 0, "nothing stale")
    }

    /// Each pane's line numbers sit on the baselines of their rows' first lines, and the separator of each gap between
    /// two changes runs where the text draws its own; with `measuredTops`, each row's top is where a full layout of
    /// its pane's text puts it.
    static func expectAligned(
        _ panes: [AlignedPane], measuredBy measuredTops: (@MainActor (AlignedPane) -> [Int: CGFloat])? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        var separators = 0
        for pane in panes {
            // Read first: asking the gutter lays rows out, which could move the ones the text placed from estimates.
            let lines = pane.shownLines()
            try #require(lines.count >= 5, "rows show", sourceLocation: sourceLocation)
            let ascender = pane.rendered.palette.gutterFont.ascender
            let numbers = pane.gutter.lineNumberFrames(in: pane.gutter.visibleRect)
            let measured = measuredTops?(pane)
            for (row, line) in lines {
                let number = try #require(numbers[row], "row \(row) has a number", sourceLocation: sourceLocation)
                let baseline = pane.gutter.convert(NSPoint(x: 0, y: number.minY + ascender), to: nil).y
                let middle = pane.gutter.convert(NSPoint(x: 0, y: number.midY), to: nil).y
                #expect(
                    abs(baseline - line.baseline) < 0.5, "row \(row)'s number on its baseline",
                    sourceLocation: sourceLocation)
                #expect(
                    line.frame.minY <= middle && middle <= line.frame.maxY, "row \(row)'s number within its line",
                    sourceLocation: sourceLocation)
                if let measured {
                    #expect(
                        abs(line.top - (measured[row] ?? .nan)) < 0.5, "row \(row) where a full layout puts it",
                        sourceLocation: sourceLocation)
                }
            }
            let gutterSeparators = pane.gutterSeparators()
            for gap in pane.rendered.gaps where gap.hasSeparator {
                guard let gutter = gutterSeparators[gap.marker.key], lines[gap.boundary - 1] != nil,
                    let text = pane.textSeparator(afterRow: gap.boundary - 1)
                else { continue }
                #expect(abs(gutter - text) < 0.5, "the separator level with its band", sourceLocation: sourceLocation)
                separators += 1
            }
        }
        #expect(separators >= 1, "a separator shows", sourceLocation: sourceLocation)
    }
}

/// A card's body as the card list hosts it, inline or side by side, in a borderless window that is never ordered in;
/// each render comes with the new layouts a card makes for it.
@MainActor
final class HostedCardBody {
    private static let width: CGFloat = 600
    private let window: NSWindow
    private let host: NSHostingView<RevealCardBody>
    private let layout: CardLayout
    private let wrapMode: WrapMode
    private var layouts: CardLayouts

    init(showing diff: RenderedDiff, layout: CardLayout, wrapsLines: Bool) {
        self.layout = layout
        wrapMode = WrapMode(wrapsLines: wrapsLines, column: 0)
        layouts = CardLayouts(rendered: diff)
        host = NSHostingView(
            rootView: RevealCardBody(layouts: layouts, layout: layout, wrapMode: wrapMode, width: Self.width))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        settle()
    }

    var bounds: NSRect { host.bounds }

    /// Shows a new render of the card, as the card does when a reveal or a reload renders its file again.
    func show(_ diff: RenderedDiff) {
        layouts = CardLayouts(rendered: diff)
        host.rootView = RevealCardBody(layouts: layouts, layout: layout, wrapMode: wrapMode, width: Self.width)
        settle()
    }

    func panes() throws -> [AlignedPane] {
        try subviews(of: DiffPaneTextView.self, in: host)
            .map { textView in
                let gutter = try #require(subviews(of: DiffGutterView.self, in: host).first { $0.source === textView })
                return AlignedPane(gutter: gutter, textView: textView, rendered: try #require(gutter.rendered))
            }
    }

    /// Where a full layout of `pane`'s text puts each row: the card's own layout of it when it wraps, which the card
    /// lays out whole and aligns with the other side; otherwise one line per row, as the card measures it.
    func measuredTops(of pane: AlignedPane) -> [Int: CGFloat] {
        guard wrapMode != .none else {
            let measured = MeasuredRows(pane.rendered)
            return Dictionary(uniqueKeysWithValues: pane.rendered.rows.indices.map { ($0, measured.top(ofRow: $0)) })
        }
        let side: StaticTextLayout? =
            switch pane.rendered.side {
                case .unified: layouts.unified
                case .old: layouts.old
                case .new: layouts.new
            }
        guard let side, let content = side.layoutManager.textContentManager else { return [:] }
        let start = side.layoutManager.documentRange.location
        var tops: [Int: CGFloat] = [:]
        side.layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            tops[pane.rendered.rowIndex(containing: offset)] = fragment.layoutFragmentFrame.minY
            return true
        }
        return tops
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }

    /// The pixels once every view has drawn again.
    func redrawnPixels() throws -> LayerPixels {
        redrawAll(in: host)
        window.displayIfNeeded()
        return try pixels()
    }

    private func settle() {
        for _ in 0 ..< 2 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        }
    }
}

/// A card's panes as ``HostedCardBody`` hosts them, from the top of what shows.
struct RevealCardBody: View {
    let layouts: CardLayouts
    let layout: CardLayout
    let wrapMode: WrapMode
    let width: CGFloat

    var body: some View {
        Group {
            switch layout {
                case .inline:
                    EmbeddedDiffTextView(
                        layouts: layouts, side: .unified, gutter: .dual, width: width, wrapMode: wrapMode)
                case .split:
                    SideBySidePanes(width: width) { paneWidth in
                        EmbeddedDiffTextView(
                            layouts: layouts, side: .old, gutter: .old, width: paneWidth, wrapMode: wrapMode)
                    } trailing: { paneWidth in
                        EmbeddedDiffTextView(
                            layouts: layouts, side: .new, gutter: .new, width: paneWidth, wrapMode: wrapMode)
                    }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Asks `view` and every view in it to draw again.
@MainActor
func redrawAll(in view: NSView) {
    view.needsDisplay = true
    for subview in view.subviews { redrawAll(in: subview) }
}
