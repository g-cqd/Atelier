import KittyApp
import KittyCodecs
import Observation
import Synchronization
import Testing

@testable import KittyEditor

/// Proves the `@Observable` macro on `EditorState` and `RenderClock` behaves
/// correctly outside SwiftUI — i.e. plain `withObservationTracking` consumers
/// in `ApplicationRuntime` receive `onChange` callbacks on the next state
/// mutation. SwiftUI is not in the dependency graph at all here.
@Suite
@MainActor
struct ObservationIntegrationTests {

    private func makeState() -> EditorState {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["alpha", "beta", "gamma"]
        _ = state.drainDirtyState()
        return state
    }

    // The dirty markers (`dirtyContentAll` / `dirtyChrome`) and other
    // pure-internal state are `@ObservationIgnored` on EditorState — the
    // public observation surface is `RenderClock.tick`, advanced by
    // `mark*Dirty`. The two tests below confirm the macro DOES fire for
    // properties that are NOT ignored (`mode`, `colorScheme`), which is
    // the contract a future observer would rely on if it tracked editor
    // state directly.

    @Test
    func `withObservationTracking fires when EditorState.mode changes`() async {
        let state = makeState()
        let fired = Mutex<Bool>(false)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = state.mode
            } onChange: {
                fired.withLock { $0 = true }
                cont.resume()
            }
            Task { @MainActor in
                state.mode = .editor
            }
        }
        #expect(fired.withLock { $0 })
    }

    @Test
    func `withObservationTracking fires when EditorState.colorScheme changes`() async {
        let state = makeState()
        let fired = Mutex<Bool>(false)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = state.colorScheme
            } onChange: {
                fired.withLock { $0 = true }
                cont.resume()
            }
            Task { @MainActor in
                var swapped = state.colorScheme
                swapped.editorText = Style()
                state.colorScheme = swapped
            }
        }
        #expect(fired.withLock { $0 })
    }

    @Test
    func `mark calls advance attached RenderClock once per clean-to-dirty edge`() {
        let state = makeState()
        let clock = RenderClock()
        state.renderClock = clock
        let initial = clock.tick

        state.markContentAllDirty()
        #expect(clock.tick == initial &+ 1, "clean → dirty edge advances clock")

        state.markContentAllDirty()
        #expect(clock.tick == initial &+ 1, "already-dirty mark must not advance")

        _ = state.drainDirtyState()
        state.markChromeDirty()
        #expect(clock.tick == initial &+ 2, "next clean → dirty advances again")
    }

    @Test
    func `markLinesDirty advances clock only on new line insertion`() {
        let state = makeState()
        let clock = RenderClock()
        state.renderClock = clock
        let initial = clock.tick

        state.markLinesDirty(2..<5)
        #expect(clock.tick == initial &+ 1, "first call inserts new lines")

        state.markLinesDirty(2..<5)
        #expect(clock.tick == initial &+ 1, "same range re-marked: no insertion, no advance")

        state.markLinesDirty(10..<11)
        #expect(clock.tick == initial &+ 2, "new line inserted: advance")
    }

    @Test
    func `synchronous burst of EditorState mutations coalesces into one onChange`() async {
        // This is the contract the dirty pipeline relies on: a single event
        // handler that fires several mark*Dirty calls in one main-actor entry
        // must wake the render loop exactly once. Without it we'd risk
        // flooding the input source with redundant .refresh injections.
        let state = makeState()
        let clock = RenderClock()
        state.renderClock = clock
        let fireCount = Mutex<Int>(0)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = clock.tick
            } onChange: {
                fireCount.withLock { $0 &+= 1 }
                cont.resume()
            }
            Task { @MainActor in
                state.markContentAllDirty()
                state.markChromeDirty()
                state.markLinesDirty(0..<5)
            }
        }
        #expect(fireCount.withLock { $0 } == 1)
    }

    @Test
    func `EditorState without attached clock still works (no crash, no observation)`() {
        // The `renderClock` is `nil` by default. mark*Dirty must remain a
        // valid operation — only the wake-up side effect is dropped.
        let state = makeState()
        #expect(state.renderClock == nil)
        state.markContentAllDirty()
        #expect(state.dirtyContentAll)
    }
}
