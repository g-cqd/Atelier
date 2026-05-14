import KittyRenderer
import KittyText
import Testing

@testable import KittyCode

/// Audit NF2 — `wrapCache.invalidate()` cleared the entire visual-row
/// cache on every per-line edit, forcing the next viewport to walk all
/// lines and rebuild from scratch. The new `invalidateLines(...)` path
/// patches only the affected lines and re-fills the visual-offset
/// prefix-sum from the change point. These tests pin both the patch
/// arithmetic and the invariant-mismatch fallback.
@Suite
@MainActor
struct WrapCacheIncrementalTests {

    private func makeSUT(lineCount: Int) -> (state: EditorState, pipeline: RenderPipeline) {
        let content = (0..<lineCount).map { "line \($0)" }
        return makeKittyCodeNavigationContext(fileContent: content)
    }

    @Test
    func `same-line edit patches only that line in wrapCache`() {
        let sut = makeSUT(lineCount: 20)
        sut.state.buildWrapCache(contentWidth: 80)
        let originalWrapCounts = sut.state.wrapCache.lineWrapCounts
        let originalTotal = sut.state.wrapCache.totalRowCount

        sut.state.cursorRow = 5
        sut.state.cursorCol = 0
        insertText("X", into: sut.state)

        // Line 5 still fits in 80 columns; wrap count remains 1.
        #expect(sut.state.wrapCache.lineWrapCounts == originalWrapCounts)
        #expect(sut.state.wrapCache.totalRowCount == originalTotal)
        // Cache was patched (not torn down) — invariants survive.
        #expect(sut.state.wrapCache.contentWidth == 80)
        // visualOffsets prefix-sum invariant still holds.
        let offsets = sut.state.wrapCache.visualOffsets
        for index in 1..<offsets.count {
            #expect(offsets[index] == offsets[index - 1] + originalWrapCounts[index - 1])
        }
    }

    @Test
    func `single-line edit that crosses the wrap boundary updates only that entry`() {
        // Narrow content width so a moderately-long line wraps onto two rows.
        let sut = makeSUT(lineCount: 10)
        sut.state.buildWrapCache(contentWidth: 10)
        let beforeRow5 = sut.state.wrapCache.lineWrapCounts[5]
        let beforeTotal = sut.state.wrapCache.totalRowCount

        // Insert enough characters at line 5 to push it across the wrap boundary.
        sut.state.cursorRow = 5
        sut.state.cursorCol = 0
        for _ in 0..<15 {
            insertText("A", into: sut.state)
        }

        let afterRow5 = sut.state.wrapCache.lineWrapCounts[5]
        #expect(afterRow5 > beforeRow5, "line 5 wraps onto more rows after the long insertion")

        // Total grew by exactly the per-line delta on row 5; every other
        // entry is unchanged.
        let delta = afterRow5 - beforeRow5
        #expect(sut.state.wrapCache.totalRowCount == beforeTotal + delta)
        for index in sut.state.wrapCache.lineWrapCounts.indices where index != 5 {
            #expect(sut.state.wrapCache.lineWrapCounts[index] == 1)
        }
    }

    @Test
    func `inserting a new line extends lineWrapCounts and visualOffsets`() {
        let sut = makeSUT(lineCount: 10)
        sut.state.buildWrapCache(contentWidth: 80)
        let beforeCount = sut.state.wrapCache.lineWrapCounts.count
        let beforeOffsetsCount = sut.state.wrapCache.visualOffsets.count

        // Insert a newline at the start of line 3 — splits line 3 into two
        // lines (effectively inserting one new line).
        sut.state.cursorRow = 3
        sut.state.cursorCol = 0
        insertText("\n", into: sut.state)

        #expect(sut.state.wrapCache.lineWrapCounts.count == beforeCount + 1)
        #expect(sut.state.wrapCache.visualOffsets.count == beforeOffsetsCount + 1)

        // Offsets remain a strictly non-decreasing prefix-sum.
        let offsets = sut.state.wrapCache.visualOffsets
        for index in 1..<offsets.count {
            #expect(offsets[index] >= offsets[index - 1])
        }
        // Last offset + last line's wrap count == totalRowCount.
        let last = sut.state.wrapCache.lineWrapCounts.count - 1
        #expect(
            offsets[last] + sut.state.wrapCache.lineWrapCounts[last]
                == sut.state.wrapCache.totalRowCount
        )
    }

    @Test
    func `invalidateLines falls back to full invalidate when contentWidth differs`() {
        // Cache is unbuilt (contentWidth == -1). Any incremental call must
        // degrade gracefully — the cache should remain in its empty state,
        // not crash or partially populate.
        let sut = makeSUT(lineCount: 5)
        #expect(sut.state.wrapCache.contentWidth == -1)

        sut.state.cursorRow = 2
        insertText("Y", into: sut.state)

        // Still empty: incremental call saw a non-positive contentWidth and
        // fell back to `invalidate()`.
        #expect(sut.state.wrapCache.lineWrapCounts.isEmpty)
        #expect(sut.state.wrapCache.visualOffsets.isEmpty)
        #expect(sut.state.wrapCache.contentWidth == -1)
    }

    @Test
    func `subsequent buildWrapCache produces the same shape as a from-scratch rebuild`() {
        // Functional cross-check: an incremental patch followed by a normal
        // rebuild call must end up identical to a from-scratch rebuild of
        // the same final document state.
        let sut1 = makeSUT(lineCount: 10)
        sut1.state.buildWrapCache(contentWidth: 12)
        sut1.state.cursorRow = 4
        sut1.state.cursorCol = 0
        for _ in 0..<20 {
            insertText("A", into: sut1.state)
        }
        sut1.state.buildWrapCache(contentWidth: 12)
        let incremental = sut1.state.wrapCache

        let sut2 = makeSUT(lineCount: 10)
        sut2.state.cursorRow = 4
        sut2.state.cursorCol = 0
        for _ in 0..<20 {
            insertText("A", into: sut2.state)
        }
        sut2.state.buildWrapCache(contentWidth: 12)
        let fromScratch = sut2.state.wrapCache

        #expect(incremental.lineWrapCounts == fromScratch.lineWrapCounts)
        #expect(incremental.visualOffsets == fromScratch.visualOffsets)
        #expect(incremental.totalRowCount == fromScratch.totalRowCount)
    }
}
