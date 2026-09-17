import AtelierText
import Foundation
import KittyRenderer
import KittyWorkspace
import Testing

@testable import KittyEditor

/// Guards that the per-keystroke edit cost no longer scales with file size
/// after the dirty-pipeline work (phases 1–4).
///
/// These are correctness guards: they run a fixed sequence on a small and a
/// large file and assert that the dirty-region marker behaviour is what the
/// renderer will rely on — no wall-clock duration is compared in the default
/// run (`AGENTS.md`). The one absolute-timing check is an opt-in benchmark
/// gated behind `ATELIER_BENCH`, which prints its measurement instead of
/// asserting on it.
@Suite
@MainActor
struct DirtyPipelinePerfTests {
    private func makeSUT(lineCount: Int) -> (state: EditorState, pipeline: RenderPipeline) {
        let content = (0 ..< lineCount).map { "line \($0)" }
        return EditorTestHarness.make(fileContent: content)
    }

    @Test
    func `same-line edit marks only that line on a small file`() {
        let sut = makeSUT(lineCount: 10)
        _ = sut.state.drainDirtyState()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 1
        insertText("X", into: sut.state)
        #expect(!sut.state.dirtyContentAll)
        #expect(sut.state.dirtyContentLines == [0])
    }

    @Test
    func `same-line edit marks only that line on a large file`() {
        let sut = makeSUT(lineCount: 10_000)
        _ = sut.state.drainDirtyState()
        sut.state.cursorRow = 5_000
        sut.state.cursorCol = 1
        insertText("X", into: sut.state)
        #expect(!sut.state.dirtyContentAll)
        #expect(sut.state.dirtyContentLines == [5_000])
    }

    @Test
    func `dirty footprint is independent of file size for same-line edits`() {
        let small = makeSUT(lineCount: 10)
        _ = small.state.drainDirtyState()
        small.state.cursorRow = 0
        small.state.cursorCol = 1
        insertText("X", into: small.state)

        let large = makeSUT(lineCount: 10_000)
        _ = large.state.drainDirtyState()
        large.state.cursorRow = 5_000
        large.state.cursorCol = 1
        insertText("X", into: large.state)

        #expect(small.state.dirtyContentLines.count == large.state.dirtyContentLines.count)
    }

    @Test
    func `small downward scroll marks only the exposed strip`() {
        let sut = makeSUT(lineCount: 1_000)
        sut.state.lastRenderRows = 24
        _ = sut.state.drainDirtyState()
        sut.state.scrollOffset = 2
        #expect(!sut.state.dirtyContentAll)
        #expect(sut.state.dirtyContentLines.count == 2)
    }

    @Test
    func `small upward scroll marks only the exposed strip`() {
        let sut = makeSUT(lineCount: 1_000)
        sut.state.lastRenderRows = 24
        sut.state.scrollOffset = 100
        _ = sut.state.drainDirtyState()
        sut.state.scrollOffset = 95
        #expect(!sut.state.dirtyContentAll)
        #expect(sut.state.dirtyContentLines.count == 5)
    }

    /// Absolute per-keystroke time on a large file. The remaining O(N) cost
    /// (`BufferEditSnapshot.contentFingerprint` walks the whole rope once per
    /// edit) is bounded — for 10 000 short lines we're well under a single
    /// rendered frame's worth of time even in debug builds. Machine-dependent
    /// wall-clock timing may not gate the default run (`AGENTS.md`), so this
    /// only runs and prints its measurement under `ATELIER_BENCH=1 swift test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `large-file keystroke stays below 15ms in debug`() {
        let sut = makeSUT(lineCount: 10_000)
        sut.state.cursorRow = 5_000
        sut.state.cursorCol = 0

        let iterations = 100
        let start = ContinuousClock.now
        for _ in 0 ..< iterations {
            insertText("X", into: sut.state)
        }
        let elapsed = start.duration(to: .now)
        let elapsedMs =
            Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        let perKeystrokeMs = elapsedMs / Double(iterations)
        print("per-keystroke on a 10k-line file: \(perKeystrokeMs) ms (budget 15 ms)")
    }
}
