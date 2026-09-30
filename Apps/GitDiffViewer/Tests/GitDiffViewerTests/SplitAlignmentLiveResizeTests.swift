import AemiTesting
import AppKit
import Testing

@testable import DiffTextKit

/// The split view aligns its rows once a live resize ends, not at every step of it (text-renderer.md §5, M0 item 7).
@MainActor
@Suite(.mainActorLane)
struct SplitAlignmentLiveResizeTests {
    @Test
    func `a live resize holds the alignment back until it ends`() {
        let controller = SplitPaneController(clock: TestClock())
        controller.liveResize = { true }

        controller.scheduleAlignment()
        #expect(controller.pendingAlignment == nil)

        controller.liveResize = { false }
        controller.liveResizeDidEnd()
        #expect(controller.pendingAlignment != nil)
        controller.pendingAlignment?.cancel()
    }

    @Test
    func `the end of a live resize that held nothing back schedules nothing`() {
        let controller = SplitPaneController(clock: TestClock())
        controller.liveResize = { false }

        controller.liveResizeDidEnd()
        #expect(controller.pendingAlignment == nil)
    }

    @Test
    func `a pane's text view tells its split view the live resize ended`() {
        let controller = SplitPaneController(clock: TestClock())
        let textView = DiffPaneTextView(usingTextLayoutManager: true)
        controller.register(nil, textView: textView)
        controller.liveResize = { true }
        controller.scheduleAlignment()

        controller.liveResize = { false }
        textView.viewDidEndLiveResize()
        #expect(controller.pendingAlignment != nil)
        controller.pendingAlignment?.cancel()
    }
}
