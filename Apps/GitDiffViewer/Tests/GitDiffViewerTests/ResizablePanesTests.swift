import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffTextKit

/// The divider between a file's two panes (book DIFF-01): dragging it resizes the panes side by side and stacked,
/// within a minimum for each; a double click splits them evenly again; the ratio is the window's own and the next
/// window opens with it; and the panes keep in step, below the bars, after a resize.
@MainActor
@Suite(.mainActorLane)
struct ResizablePanesTests {
    private static let size = NSSize(width: 600, height: 400)
    private nonisolated static let splitLayouts: [PaneLayout] = [.sideBySide, .stacked]

    private let scratchDefaults = ScratchDefaults(tag: "resizablePanes")

    private func makeSUT(
        _ layout: PaneLayout, text: PaneText = .lines(60), wrapsLines: Bool = false, underBars: CGFloat = 0,
        ratio: Binding<Double>? = nil
    ) -> HostedPanes {
        HostedPanes(
            showing: text, layout: layout, wrapsLines: wrapsLines, size: Self.size, underBars: underBars, ratio: ratio)
    }

    @Test(arguments: splitLayouts)
    func `dragging the divider moves the length it is dragged from the new pane to the old one`(
        layout: PaneLayout
    ) throws {
        let sut = makeSUT(layout)
        let before = try PaneLengths(sut, layout)

        try sut.dragDivider(by: 40)

        let after = try PaneLengths(sut, layout)
        #expect(abs(after.old - before.old - 40) < 0.5)
        #expect(abs(after.new - before.new + 40) < 0.5)
    }

    @Test(arguments: splitLayouts, [-1_000, 1_000] as [CGFloat])
    func `a drag stops where a pane reaches its minimum`(layout: PaneLayout, distance: CGFloat) throws {
        let sut = makeSUT(layout)

        try sut.dragDivider(by: distance)

        let lengths = try PaneLengths(sut, layout)
        let shorter = distance < 0 ? lengths.old : lengths.new
        #expect(abs(shorter - PaneSplit.minimumPaneLength) < 0.5)
    }

    @Test
    func `stacked, the pane beneath the bars keeps its minimum below them`() throws {
        let bars: CGFloat = 40
        let sut = makeSUT(.stacked, underBars: bars)

        try sut.dragDivider(by: -1_000)

        let lengths = try PaneLengths(sut, .stacked)
        #expect(abs(lengths.old - bars - PaneSplit.minimumPaneLength) < 0.5)
    }

    @Test(arguments: splitLayouts)
    func `a double click on the divider splits the panes evenly again`(layout: PaneLayout) throws {
        let store = PaneRatioStore()
        let sut = makeSUT(layout, ratio: store.binding)
        try sut.dragDivider(by: 60)

        try sut.doubleClickDivider()

        let lengths = try PaneLengths(sut, layout)
        #expect(store.ratio == PaneSplit.evenRatio)
        // Whole points each, so an odd length leaves the old pane the extra one.
        #expect(abs(lengths.old - lengths.new) <= 1)
    }

    @Test(arguments: splitLayouts)
    func `the divider draws a line between the panes and takes the pointer on either side of it`(
        layout: PaneLayout
    ) throws {
        let sut = makeSUT(layout)
        let divider = try #require(sut.divider)
        let lengths = try PaneLengths(sut, layout)
        let middle = divider.convert(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
        let along = { (offset: CGFloat) in
            layout == .stacked ? NSPoint(x: middle.x, y: middle.y + offset) : NSPoint(x: middle.x + offset, y: middle.y)
        }

        #expect(abs(lengths.gap - PaneSplit.dividerThickness) < 0.01)
        for offset in [-3, 0, 3] as [CGFloat] { #expect(sut.hit(at: along(offset)) === divider) }
        for offset in [-8, 8] as [CGFloat] { #expect(sut.hit(at: along(offset)) !== divider) }
    }

    @Test
    func `a dragged ratio is the window's own, and the next window opens with it`() throws {
        let window = ViewerSettings(defaults: scratchDefaults.defaults)
        let other = ViewerSettings(defaults: scratchDefaults.defaults)
        let sut = makeSUT(.sideBySide, ratio: Binding(get: { window.paneRatio }, set: { window.paneRatio = $0 }))

        try sut.dragDivider(by: 90)

        let dragged = try PaneLengths(sut, .sideBySide)
        let next = ViewerSettings(defaults: scratchDefaults.defaults)
        let reopened = makeSUT(.sideBySide, ratio: Binding(get: { next.paneRatio }, set: { next.paneRatio = $0 }))
        #expect(window.paneRatio > PaneSplit.evenRatio)
        #expect(other.paneRatio == PaneSplit.evenRatio)
        #expect(next.paneRatio == window.paneRatio)
        #expect(abs(try PaneLengths(reopened, .sideBySide).old - dragged.old) < 0.5)
    }

    @Test(arguments: splitLayouts)
    func `after a resize the panes still scroll together below the bars`(layout: PaneLayout) throws {
        let bars: CGFloat = 40
        let sut = makeSUT(layout, underBars: bars)
        try sut.dragDivider(by: 50)
        let upper = try #require(try sut.panes().first)

        upper.clip.scroll(to: NSPoint(x: 0, y: 150))
        upper.clip.enclosingScrollView?.reflectScrolledClipView(upper.clip)
        sut.settleNow()

        let panes = try sut.panes()
        #expect(panes[0].clip.contentInsets.top == bars)
        #expect(panes[1].clip.contentInsets.top == (layout == .stacked ? 0 : bars))
        #expect(abs(panes[1].shownTop - panes[0].shownTop) < 0.5)
    }

    /// To 180 points of the 600 either way: the narrower pane wraps the long rows onto more lines than the other.
    @Test(arguments: [-120, 120] as [CGFloat])
    func `after a resize wrapped rows line up again side by side`(distance: CGFloat) async throws {
        let sut = makeSUT(.sideBySide, text: .longLines(60), wrapsLines: true)
        try await sut.alignSides()

        try sut.dragDivider(by: distance)
        try await withMainThreadBound("Aligning the rows after the drag") { try await sut.alignSides() }

        let panes = try sut.panes()
        // Row 7 wraps, onto more lines in the narrower pane than in the other, down past the pane's bottom: the row after
        // it starts where it ends.
        for row in [6, 7] {
            #expect(abs(try panes[0].top(ofRow: row) - panes[1].top(ofRow: row)) < 0.5, "row \(row)")
        }
        #expect(abs(try panes[0].bottom(ofRow: 7) - panes[1].bottom(ofRow: 7)) < 0.5)
    }
}

/// How long each pane of a file is along the axis the divider moves on, and the gap between them.
@MainActor
private struct PaneLengths {
    let old: CGFloat
    let new: CGFloat
    let gap: CGFloat

    init(_ sut: HostedPanes, _ layout: PaneLayout) throws {
        let frames = sut.paneViews().map { $0.convert($0.bounds, to: nil) }
        try #require(frames.count == 2)
        // Window coordinates grow upwards: stacked, the old pane is the one above.
        if layout == .stacked {
            old = frames[0].height
            new = frames[1].height
            gap = frames[0].minY - frames[1].maxY
        } else {
            old = frames[0].width
            new = frames[1].width
            gap = frames[1].minX - frames[0].maxX
        }
    }
}

/// The arithmetic of the split, with no view.
struct PaneSplitTests {
    @Test
    func `a ratio past either bound stops where the pane it shrinks keeps its minimum`() {
        let length: CGFloat = 601
        let least = Double(PaneSplit.minimumPaneLength / 600)

        #expect(PaneSplit.clamped(0.01, length: length) == least)
        #expect(PaneSplit.clamped(0.99, length: length) == 1 - least)
        #expect(PaneSplit.clamped(0.3, length: length) == 0.3)
    }

    @Test(arguments: [.nan, .infinity, -.infinity] as [Double])
    func `a ratio that is not a number splits evenly`(ratio: Double) {
        #expect(PaneSplit.clamped(ratio, length: 600) == PaneSplit.evenRatio)
    }

    @Test
    func `a length too short for two panes at their minimum splits evenly`() {
        let length = 2 * PaneSplit.minimumPaneLength

        #expect(PaneSplit.clamped(0.2, length: length) == PaneSplit.evenRatio)
        #expect(PaneSplit.ratio(draggingFrom: 0.5, by: 50, length: length) == PaneSplit.evenRatio)
    }

    @Test
    func `the covered length stays with the old pane and out of the share`() {
        #expect(PaneSplit.leadingLength(ratio: 0.5, length: 441, covered: 40) == 240)
    }
}
