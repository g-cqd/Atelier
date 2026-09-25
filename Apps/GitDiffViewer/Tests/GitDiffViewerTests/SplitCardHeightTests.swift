import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A split card's height: its panes are as tall as their aligned rows, the same on every measure, and a body holding
/// real panes measures that height whatever height it is offered.
@MainActor
@Suite(.mainActorLane)
struct SplitCardHeightTests {
    private static let wide = String(repeating: "left ", count: 25)
    private static let other = String(repeating: "right ", count: 25)
    /// Row two wraps only on the left and row four only on the right, and the last row is the same on both sides.
    private let old = "alpha\n\(wide)\ncommon\ngamma\nend\n"
    private let new = "alpha\nshort\ncommon\n\(other)\nend\n"

    private func makeSUT() throws -> (layouts: CardLayouts, old: StaticTextLayout, new: StaticTextLayout) {
        let layouts = CardLayouts(rendered: DiffRenderer.render(oldText: old, newText: new, language: .plain))
        return try (layouts, #require(layouts.old), #require(layouts.new))
    }

    private func alignedHeight(_ old: StaticTextLayout, _ new: StaticTextLayout) -> CGFloat {
        let rows = zip(old.rowHeights(), new.rowHeights()).reduce(0) { $0 + max($1.0, $1.1) }
        return (rows + 2 * StaticTextLayout.verticalInset).rounded(.up)
    }

    @Test(arguments: [WrapMode.viewport, .column(20)])
    func `a wrapping split card is as tall as its aligned rows, whichever side wraps a row`(mode: WrapMode) throws {
        let sut = try makeSUT()
        sut.layouts.prepareSplit(width: 120, mode: mode)
        #expect(sut.old.rowHeights() != sut.new.rowHeights())
        #expect(sut.old.height == alignedHeight(sut.old, sut.new))
        #expect(sut.new.height == sut.old.height)
    }

    @Test(arguments: [WrapMode.none, .viewport])
    func `a card pane is its rows, with no space above the first or below the last`(mode: WrapMode) throws {
        let unified = try #require(try makeSUT().layouts.unified)
        unified.layOut(mode: mode, viewportWidth: 240)
        #expect(unified.height == CGFloat(unified.rowHeights().reduce(0, +)).rounded(.up))
        let sut = try makeSUT()
        sut.layouts.prepareSplit(width: 120, mode: .none)
        #expect(sut.old.height == (CGFloat(sut.old.rendered.rows.count) * sut.old.rendered.lineHeight).rounded(.up))
    }

    @Test
    func `heights stay the same across measures, repeated preparations and a width round trip`() throws {
        let sut = try makeSUT()
        sut.layouts.prepareSplit(width: 120, mode: .viewport)
        let first = sut.old.height
        #expect(sut.old.height == first)
        sut.layouts.prepareSplit(width: 120, mode: .viewport)
        #expect(sut.old.height == first)
        sut.layouts.prepareSplit(width: 400, mode: .viewport)
        #expect(sut.old.height < first)
        sut.layouts.prepareSplit(width: 120, mode: .viewport)
        #expect(sut.old.height == first)
    }

    @Test
    func `turning wrapping off measures the card again, as tall as one that never wrapped`() throws {
        let sut = try makeSUT()
        sut.layouts.prepareSplit(width: 120, mode: .viewport)
        let wrapped = sut.old.height
        sut.layouts.prepareSplit(width: 120, mode: .none)
        let neverWrapped = try makeSUT()
        neverWrapped.layouts.prepareSplit(width: 120, mode: .none)
        #expect(sut.old.height < wrapped)
        #expect(sut.old.height == neverWrapped.old.height)
        #expect(sut.new.height == neverWrapped.new.height)
    }

    @Test
    func `row spacing applied after a measure is part of the next measure`() throws {
        let sut = try makeSUT()
        sut.old.layOut(mode: .viewport, viewportWidth: 120)
        let unspaced = sut.old.height
        sut.old.apply(spacing: Array(repeating: 10, count: sut.old.rendered.rows.count))
        #expect(sut.old.height > unspaced)
    }

    @Test(arguments: [RenderLayout.full, .changes(context: 1, expansions: [:])])
    func `an unwrapped split side, fillers and gaps included, is exactly as tall as TextKit lays it out`(
        layout: RenderLayout
    ) throws {
        let lines = (1 ... 40).map { "let value\($0) = \($0)\n" }
        let changed = lines.enumerated().filter { $0.offset % 13 != 5 }.map(\.element).joined() + "let added = 0\n"
        let diff = DiffRenderer.render(
            oldText: lines.joined(), newText: changed, language: .plain, lineHeightMultiple: 1.2, layout: layout)
        for side in try [#require(diff.old), #require(diff.new)] {
            #expect(side.rows.contains { $0.kind == .filler })
            let analytic = StaticTextLayout(rendered: side)
            analytic.layOut(mode: .none, viewportWidth: 300)
            let laidOut = StaticTextLayout(rendered: side)
            laidOut.layOut(mode: .column(100_000), viewportWidth: 300)
            #expect(analytic.height == laidOut.height)
        }
    }

    @Test(arguments: [WrapMode.viewport, .none])
    func `a body holding real split panes measures its aligned height whatever height it is offered`(
        mode: WrapMode
    ) throws {
        let sut = try makeSUT()
        let host = NSHostingController(
            rootView: SideBySidePanes(width: 360) { width in
                EmbeddedDiffTextView(layouts: sut.layouts, side: .old, gutter: .old, width: width, wrapMode: mode)
            } trailing: { width in
                EmbeddedDiffTextView(layouts: sut.layouts, side: .new, gutter: .new, width: width, wrapMode: mode)
            })
        host.sizingOptions = []
        let heights = [CGFloat.greatestFiniteMagnitude, 0, 10_000]
            .map {
                host.sizeThatFits(in: CGSize(width: 360, height: $0)).height
            }
        let expected = max(sut.old.height, sut.new.height)
        #expect(expected.isFinite && expected > 0)
        #expect(heights == [expected, expected, expected])
        #expect(host.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)).height == expected)
    }

    @Test
    func `a split body with no width yet measures a finite size`() throws {
        let sut = try makeSUT()
        let host = NSHostingController(
            rootView: SideBySidePanes(width: 0) { width in
                EmbeddedDiffTextView(layouts: sut.layouts, side: .old, gutter: .old, width: width)
            } trailing: { width in
                EmbeddedDiffTextView(layouts: sut.layouts, side: .new, gutter: .new, width: width)
            })
        host.sizingOptions = []
        for proposed in [CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude), .zero] {
            let size = host.sizeThatFits(in: proposed)
            #expect(size.width.isFinite && size.height.isFinite, "\(size)")
        }
    }
}
