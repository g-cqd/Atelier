import AppKit
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The two sides of a file follow each other by row: each shows the row the other shows at its top, as far into it,
/// though each places it after its own estimates of the rows above it, which TextKit has not laid out.
@MainActor
@Suite(.mainActorLane)
struct SplitPaneRowSyncTests {
    /// One side has laid its rows out down to the middle of the file, the other has not: their estimates of where a
    /// deep row lies differ by a line for each long line above it, which one shared offset would show as rows apart.
    @Test(arguments: [PaneLayout.sideBySide, .stacked], [false, true])
    func `scrolled deep, the other pane shows the row this one shows at its top, as far into it`(
        layout: PaneLayout, wrapsLines: Bool
    ) throws {
        let sut = HostedPanes(showing: .longLines(600), layout: layout, wrapsLines: wrapsLines, underBars: 40)
        let first = try #require(try sut.panes().first)
        let layoutManager = try #require(first.textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let middle = try #require(
            content.location(layoutManager.documentRange.location, offsetBy: first.rendered.lineStarts[300]))
        let above = try #require(NSTextRange(location: layoutManager.documentRange.location, end: middle))
        layoutManager.ensureLayout(for: above)

        first.clip.scroll(to: NSPoint(x: 0, y: first.textView.frame.height * 0.8))
        first.clip.enclosingScrollView?.reflectScrolledClipView(first.clip)
        sut.settleNow()

        let panes = try sut.panes()
        let tops = try panes.map { try $0.rowAtTop() }
        #expect(tops[0].row > 300)
        #expect(tops[1].row == tops[0].row)
        #expect(abs(tops[1].offset - tops[0].offset) < 0.5, "the offsets are \(tops.map(\.offset))")
        #expect(try !panes[1].isLaidOut(row: 100))
    }

    /// A folded function takes the same rows out of both sides, so the row below the fold one side shows at its top
    /// is the row the other shows (DIFF-03).
    @Test
    func `side by side, scrolled deep below a function folded in both panes, the other pane shows the same row`()
        throws
    {
        let sut = HostedPanes(
            showing: .longLines(600, foldedFrom: 20, through: 200), layout: .sideBySide, wrapsLines: false)
        let first = try #require(try sut.panes().first)
        let band = try #require(first.rendered.folds.first?.bandRow)
        for pane in try sut.panes() { #expect(pane.rendered.folds.map(\.bandRow) == [band]) }
        let layoutManager = try #require(first.textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let middle = try #require(
            content.location(layoutManager.documentRange.location, offsetBy: first.rendered.lineStarts[band + 150]))
        let above = try #require(NSTextRange(location: layoutManager.documentRange.location, end: middle))
        layoutManager.ensureLayout(for: above)

        first.clip.scroll(to: NSPoint(x: 0, y: first.textView.frame.height * 0.8))
        first.clip.enclosingScrollView?.reflectScrolledClipView(first.clip)
        sut.settleNow()

        let panes = try sut.panes()
        let tops = try panes.map { try $0.rowAtTop() }
        #expect(tops[0].row > band + 150)
        #expect(tops[1].row == tops[0].row)
        #expect(abs(tops[1].offset - tops[0].offset) < 0.5, "the offsets are \(tops.map(\.offset))")
    }

    /// Side by side, as inline, a deep first change is placed after the estimates of the rows above it, which are
    /// not laid out: laying them out took most of opening a long file (`FirstChangePlacementBenchmark`).
    @Test(arguments: [false, true])
    func `side by side, a deep first change opens three lines below each pane's top, the rows above not laid out`(
        wrapsLines: Bool
    ) throws {
        let sut = HostedPanes(showing: .longLines(600, changedAt: 540), layout: .sideBySide, wrapsLines: wrapsLines)

        let row = try #require(sut.requestedRow)
        for pane in try sut.panes() {
            #expect(pane.rendered.lineStarts[row] > RowPlacement.textLaidOutAbove)
            let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
            #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")
            #expect(try !pane.isLaidOut(row: 100))
        }
    }
}
