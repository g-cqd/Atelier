import AppKit
import Testing

@testable import DiffTextKit

/// Side by side and wrapped, a file whose two sides wrap onto different numbers of lines opens with its first change
/// three lines below the pane's top: the row spacing that lines the sides up is an edit of the text, during which a
/// pane is not sized, and the change is placed only once it is.
@MainActor
@Suite(.mainActorLane)
struct WrappedPlacementTests {
    /// Panes 2 pt narrower each than the default window gives them, where the long lines of
    /// `PaneText.longLines(_:changedAt:)` wrap differently on the two sides.
    private static let size = NSSize(width: 596, height: HostedPanes.paneHeight)

    @Test(arguments: [0, 40] as [CGFloat])
    func `sides that wrap differently open with the first change three lines below the top`(bars: CGFloat)
        async throws
    {
        try await withMainThreadBound("Opening a side-by-side wrapped file") {
            let sut = HostedPanes(
                showing: .longLines(60, changedAt: 30), layout: .sideBySide, wrapsLines: true, size: Self.size,
                underBars: bars)
            try await sut.alignSides()

            let row = try #require(sut.requestedRow)
            for pane in try sut.panes() {
                let below = try pane.top(ofRow: row) - pane.shownTop
                #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")
            }
        }
    }
}
