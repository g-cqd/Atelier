import Foundation
import KittyRenderer
import KittyText
import Testing

@testable import KittyCode

/// Microbenchmarks that assert the per-keystroke edit cost no longer scales
/// with file size after the dirty-pipeline work (phases 1–4).
///
/// These are not pure benchmarks — they're correctness guards: they run a
/// fixed sequence on a small and a large file, check the operation completed,
/// and assert that the dirty-region marker behaviour is what the renderer
/// will rely on. Wall-clock timing is recorded for observability only; we
/// don't fail on absolute durations (machine-dependent).
@Suite
@MainActor
struct DirtyPipelinePerfTests {

    private func makeSUT(lineCount: Int) -> (state: EditorState, pipeline: RenderPipeline) {
        let content = (0..<lineCount).map { "line \($0)" }
        return makeKittyCodeNavigationContext(fileContent: content)
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

    @Test
    func `large-file keystroke stays below 5ms in debug`() {
        // Absolute per-keystroke time on a large file. The remaining O(N)
        // cost (BufferEditSnapshot.contentFingerprint walks the whole rope
        // once per edit) is bounded — for 10 000 short lines we're well under
        // a single rendered frame's worth of time even in debug builds.
        let sut = makeSUT(lineCount: 10_000)
        sut.state.cursorRow = 5_000
        sut.state.cursorCol = 0

        let iterations = 100
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            insertText("X", into: sut.state)
        }
        let elapsed = start.duration(to: .now)
        let elapsedMs = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        let perKeystrokeMs = elapsedMs / Double(iterations)
        // 5ms gives ~200 keystrokes/sec headroom in debug mode; release builds
        // are usually 3–5× faster. Threshold catches a real regression while
        // tolerating noisy CI clocks.
        #expect(
            perKeystrokeMs < 5.0,
            "per-keystroke \(perKeystrokeMs) ms exceeds 5 ms budget on a 10k-line file"
        )
    }
}
