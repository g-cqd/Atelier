import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file's panes run beneath the tab bar, which they take as safe area of their own: the text starts below it,
/// scrolls beneath it with the system's scroll edge effect, and every placement, the gutter and the minimap count the
/// pane's top from below it (book TAB-09). Side by side both panes run beneath it; stacked, the upper one alone.
@MainActor
@Suite(.mainActorLane)
struct FilePaneUnderBarsTests {
    private static let bars: CGFloat = 40

    @Test(arguments: PaneLayout.allCases)
    func `beneath the bars, a file opens with its first row just below them`(layout: PaneLayout) throws {
        let plain = HostedPanes(showing: .lines(60), layout: layout, wrapsLines: false)
        let sut = HostedPanes(showing: .lines(60), layout: layout, wrapsLines: false, underBars: Self.bars)

        let expected = try plain.panes().map { try $0.top(ofRow: 0) - $0.shownTop }
        let panes = try sut.panes()

        #expect(panes.first?.clip.contentInsets.top == Self.bars)
        for (pane, offset) in zip(panes, expected) {
            #expect(abs(try pane.top(ofRow: 0) - pane.shownTop - offset) < 0.5)
        }
    }

    @Test(arguments: PaneLayout.allCases, [false, true])
    func `beneath the bars, a file opens with its first change three lines below them`(
        layout: PaneLayout, wrapsLines: Bool
    ) async throws {
        let sut = HostedPanes(
            showing: .longLines(60, changedAt: 30), layout: layout, wrapsLines: wrapsLines, underBars: Self.bars)
        try await sut.alignSides()

        let row = try #require(sut.requestedRow)
        for pane in try sut.panes() {
            let below = try pane.top(ofRow: row) - pane.shownTop
            #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below what the bars leave")
        }
    }

    @Test
    func `a file that fits below the bars shows whole there, with nothing to scroll`() throws {
        let sut = HostedPanes(showing: .lines(6), layout: .inline, wrapsLines: false, underBars: Self.bars)

        let pane = try #require(try sut.panes().first)

        #expect(pane.clip.bounds.minY == -Self.bars)
        #expect(pane.textView.frame.height <= pane.clip.bounds.height - Self.bars + 0.5)
    }

    @Test
    func `stacked, the lower pane shows the row the upper one shows below the bars`() throws {
        let sut = HostedPanes(showing: .lines(60), layout: .stacked, wrapsLines: false, underBars: Self.bars)
        let upper = try #require(try sut.panes().first)

        upper.clip.scroll(to: NSPoint(x: 0, y: 150))
        upper.clip.enclosingScrollView?.reflectScrolledClipView(upper.clip)
        sut.settleNow()

        let panes = try sut.panes()
        #expect(panes[1].clip.contentInsets.top == 0)
        #expect(abs(panes[1].shownTop - panes[0].shownTop) < 0.5)
    }

    @Test
    func `the gutter draws no line number beneath the bars`() throws {
        let sut = HostedPanes(showing: .lines(60), layout: .inline, wrapsLines: false, underBars: Self.bars)
        let pane = try #require(try sut.panes().first)
        // Rows scroll beneath the bars.
        pane.clip.scroll(to: NSPoint(x: 0, y: 5 * pane.lineHeight))
        pane.clip.enclosingScrollView?.reflectScrolledClipView(pane.clip)
        sut.settleNow()
        let gutter = try #require(try sut.shownPanes().first).gutter
        let bitmap = try #require(gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds))
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / gutter.bounds.width

        // Across the gutter, less its separator, the strip beneath the bars is its background alone.
        let background = bitmap.colorAt(x: 0, y: 0)
        let columns = 0 ..< Int((gutter.bounds.width - 1) * scale)
        let rows = 0 ..< Int(Self.bars * scale)
        let marked = rows.contains { y in columns.contains { bitmap.colorAt(x: $0, y: y) != background } }
        #expect(!marked)
        // Below the bars, the numbers show.
        let belowBars = Int(Self.bars * scale) ..< Int((Self.bars + 2 * pane.lineHeight) * scale)
        #expect(belowBars.contains { y in columns.contains { bitmap.colorAt(x: $0, y: y) != background } })
    }

    @Test
    func `the minimap maps what shows below the bars`() throws {
        let sut = HostedPanes(showing: .lines(60), layout: .inline, wrapsLines: false, underBars: Self.bars)
        let pane = try #require(sut.paneViews().first)

        #expect(pane.minimapView.frame.maxY == pane.bounds.height - Self.bars)
        #expect(pane.minimapView.frame.minY == 0)
    }
}
