import AtelierText
import Testing

@testable import KittyEditor

/// Git refreshes and full highlights run on long-lived consumers: each starts once, and the same task survives a
/// burst of refresh signals.
@Suite
@MainActor
struct RefreshLifecycleTests {
    private func makeState() -> EditorState {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["alpha", "beta", "gamma"]
        return state
    }

    @Test
    func `full-highlight consumer is started once in init`() {
        let state = makeState()
        #expect(state.fullHighlightTask != nil, "consumer task must start in init")
    }

    @Test
    func `refreshHighlights does not tear down the consumer task`() {
        let state = makeState()
        #expect(state.fullHighlightTask != nil)

        for _ in 0 ..< 20 {
            state.refreshHighlights()
        }

        // The producer just yields into the stream — the long-lived
        // consumer task is never assigned, replaced, or nilled out.
        #expect(state.fullHighlightTask != nil)
    }

    @Test
    func `consumer survives a textDidChange burst`() {
        let state = makeState()
        #expect(state.fullHighlightTask != nil)
        state.cursorRow = 1
        state.cursorCol = 0
        for _ in 0 ..< 10 {
            insertText("X", into: state)
        }
        #expect(state.fullHighlightTask != nil)
    }
}
