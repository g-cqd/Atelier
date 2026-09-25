import AppKit
import SwiftUI
import Testing

@testable import DiffTextKit

/// ``SideBySidePanes``: two panes and a divider whose height is the taller pane's, whatever height is proposed.
@MainActor
@Suite(.mainActorLane)
struct SideBySidePanesTests {
    private func makeSUT(width: CGFloat = 301) -> NSHostingController<SideBySidePanes<some View, some View>> {
        let host = NSHostingController(
            rootView: SideBySidePanes(width: width) { _ in
                Color.clear.frame(height: 100)
            } trailing: { _ in
                Color.clear.frame(height: 60)
            })
        host.sizingOptions = []
        return host
    }

    @Test(arguments: [0, 50, 10_000, .greatestFiniteMagnitude, .infinity] as [CGFloat])
    func `a pair measures as tall as its taller pane whatever height it is offered`(proposedHeight: CGFloat) {
        let size = makeSUT().sizeThatFits(in: CGSize(width: 301, height: proposedHeight))
        #expect(size.height == 100)
    }

    @Test(arguments: [(301, 150), (300, 149.5), (1, 0), (0, 0)] as [(CGFloat, CGFloat)])
    func `each pane gets half of the width the divider leaves`(width: CGFloat, paneWidth: CGFloat) {
        #expect(SideBySidePanes<EmptyView, EmptyView>.paneWidth(forWidth: width) == paneWidth)
    }

    @Test
    func `both panes are built for their share of the width`() {
        var widths: [CGFloat] = []
        _ = SideBySidePanes(width: 301) { width in
            let _ = widths.append(width)
            EmptyView()
        } trailing: { width in
            let _ = widths.append(width)
            EmptyView()
        }
        #expect(widths == [150, 150])
    }
}
