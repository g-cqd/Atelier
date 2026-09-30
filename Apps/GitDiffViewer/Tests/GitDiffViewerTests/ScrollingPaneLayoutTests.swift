import AppKit
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A scrolling pane that does not wrap lays out what it shows, not the whole document, when a text is published to
/// it (text-renderer.md §5, M0 exit criteria).
@MainActor
@Suite(.mainActorLane)
struct ScrollingPaneLayoutTests {
    @Test
    func `a published text lays out at most three times the rows that show`() throws {
        let rendered = try TextBackendBenchmark.rendered(rows: 3_000, token: "value")
        let pane = BackendPane(kind: .textKit2, showing: rendered, wrapping: .none)
        defer { pane.close() }

        let visible = pane.visibleRowCount
        #expect(visible > 0)
        #expect(pane.laidOutRows() <= 3 * visible)
    }
}
