import Testing

@testable import AtelierText
@testable import KittyWorkspace

@Suite struct BufferEditHistoryTests {
    private func makeSnapshot(
        _ text: String,
        cursor: TextCursor = TextCursor(),
        selection: TextSelection? = nil
    ) -> BufferEditSnapshot {
        BufferEditSnapshot(
            textBuffer: TextBuffer(text),
            textCursor: cursor,
            lineEnding: .lineFeed,
            selection: selection
        )
    }

    @Test func `redo applies correct snapshot after undo`() {
        let initial = makeSnapshot("initial")
        let history = BufferEditHistory(initial: initial)
        let after = makeSnapshot("after")

        history.recordChange(from: initial, to: after, coalescingWindow: nil)
        _ = history.undo(current: after)

        let redoResult = history.redo(current: initial)
        guard case .applied(let snapshot) = redoResult else {
            Issue.record("Expected .applied from redo")
            return
        }
        #expect(snapshot.textBuffer.text == "after")
    }

    @Test func `undo on empty stack returns unavailable`() {
        let initial = makeSnapshot("initial")
        let history = BufferEditHistory(initial: initial)

        let result = history.undo(current: initial)
        guard case .unavailable = result else {
            Issue.record("Expected .unavailable from undo on empty stack")
            return
        }
    }

    @Test func `isDirty returns true after change, false after markSaved`() {
        let initial = makeSnapshot("initial")
        let history = BufferEditHistory(initial: initial)
        let changed = makeSnapshot("changed")

        history.recordChange(from: initial, to: changed, coalescingWindow: nil)
        #expect(history.isDirty(current: changed))

        history.markSaved(changed)
        #expect(!history.isDirty(current: changed))
    }

    @Test func `reconcileWithRefresh with empty stacks returns false`() {
        let initial = makeSnapshot("initial")
        let history = BufferEditHistory(initial: initial)

        let invalidated = history.reconcileWithRefresh(initial)
        #expect(!invalidated)
    }

    @Test func `selection is preserved through undo redo cycle`() {
        let sel = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 3)
        )
        let initial = makeSnapshot("hello")
        let after = makeSnapshot("hello world", cursor: TextCursor(col: 11), selection: sel)
        let history = BufferEditHistory(initial: initial)

        history.recordChange(from: initial, to: after, coalescingWindow: nil)

        guard case .applied(let undone) = history.undo(current: after) else {
            Issue.record("Expected .applied from undo")
            return
        }
        #expect(undone.selection == nil)

        guard case .applied(let redone) = history.redo(current: undone) else {
            Issue.record("Expected .applied from redo")
            return
        }
        #expect(redone.selection == sel)
    }

    @Test func `maxUndoSteps prunes oldest entries`() {
        let initial = makeSnapshot("v0")
        let history = BufferEditHistory(initial: initial)
        history.maxUndoSteps = 3

        var prev = initial
        for i in 1 ... 5 {
            let next = makeSnapshot("v\(i)")
            history.recordChange(from: prev, to: next, coalescingWindow: nil)
            prev = next
        }

        #expect(history.hasUndo)

        var undoCount = 0
        var current = prev
        while case .applied(let snapshot) = history.undo(current: current) {
            undoCount += 1
            current = snapshot
        }
        #expect(undoCount == 3)
    }

    @Test func `coalescing breaks on cursor position jump`() {
        let initial = makeSnapshot("ab", cursor: TextCursor(col: 0))
        let history = BufferEditHistory(initial: initial)

        let after1 = makeSnapshot("xab", cursor: TextCursor(col: 1))
        history.recordChange(from: initial, to: after1, coalescingWindow: 10)

        // Jump cursor to col 3 (simulating arrow key movement)
        let before2 = makeSnapshot("xab", cursor: TextCursor(col: 3))
        let after2 = makeSnapshot("xaby", cursor: TextCursor(col: 4))
        history.recordChange(from: before2, to: after2, coalescingWindow: 10)

        // Should be two undo steps
        guard case .applied(let step1) = history.undo(current: after2) else {
            Issue.record("Expected first undo to apply")
            return
        }
        #expect(step1.textBuffer.text == "xab")

        guard case .applied(let step2) = history.undo(current: step1) else {
            Issue.record("Expected second undo to apply")
            return
        }
        #expect(step2.textBuffer.text == "ab")
    }

    @Test func `coalescing continues for sequential cursor advancement`() {
        let initial = makeSnapshot("", cursor: TextCursor(col: 0))
        let history = BufferEditHistory(initial: initial)

        let after1 = makeSnapshot("a", cursor: TextCursor(col: 1))
        history.recordChange(from: initial, to: after1, coalescingWindow: 10)

        // Cursor at col 1 matches after1's cursor
        let before2 = makeSnapshot("a", cursor: TextCursor(col: 1))
        let after2 = makeSnapshot("ab", cursor: TextCursor(col: 2))
        history.recordChange(from: before2, to: after2, coalescingWindow: 10)

        // Should be one undo step (coalesced)
        guard case .applied(let undone) = history.undo(current: after2) else {
            Issue.record("Expected undo to apply")
            return
        }
        #expect(undone.textBuffer.text == "")

        guard case .unavailable = history.undo(current: undone) else {
            Issue.record("Expected no more undo steps")
            return
        }
    }

    @Test func `invalidation reason set on external file change`() {
        let initial = makeSnapshot("original")
        let history = BufferEditHistory(initial: initial)
        let changed = makeSnapshot("changed")

        history.recordChange(from: initial, to: changed, coalescingWindow: nil)

        let external = makeSnapshot("external")
        _ = history.reconcileWithRefresh(external)

        #expect(history.lastInvalidationReason == .externalFileChange)
    }

    @Test func `invalidation reason set on fingerprint mismatch`() {
        let initial = makeSnapshot("original")
        let history = BufferEditHistory(initial: initial)
        let changed = makeSnapshot("changed")

        history.recordChange(from: initial, to: changed, coalescingWindow: nil)

        // Pass a snapshot with different content than what history expects
        let diverged = makeSnapshot("diverged")
        _ = history.undo(current: diverged)

        #expect(history.lastInvalidationReason == .fingerprintMismatch)
    }

    @Test func `isNextUndoAtSaveBoundary returns true when next undo reaches saved state`() {
        let initial = makeSnapshot("saved")
        let history = BufferEditHistory(initial: initial)
        let changed = makeSnapshot("changed")

        history.recordChange(from: initial, to: changed, coalescingWindow: nil)
        #expect(history.isNextUndoAtSaveBoundary)
    }

    @Test func `isNextUndoAtSaveBoundary returns false when save point is deeper`() {
        let initial = makeSnapshot("saved")
        let history = BufferEditHistory(initial: initial)
        let mid = makeSnapshot("mid")
        let latest = makeSnapshot("latest")

        history.recordChange(from: initial, to: mid, coalescingWindow: nil)
        history.recordChange(from: mid, to: latest, coalescingWindow: nil)
        #expect(!history.isNextUndoAtSaveBoundary)
    }

    @Test func `isNextUndoAtSaveBoundary returns false on empty stack`() {
        let initial = makeSnapshot("saved")
        let history = BufferEditHistory(initial: initial)
        #expect(!history.isNextUndoAtSaveBoundary)
    }

    @Test func `invalidation reason cleared on successful record`() {
        let initial = makeSnapshot("original")
        let history = BufferEditHistory(initial: initial)
        let changed = makeSnapshot("changed")

        history.recordChange(from: initial, to: changed, coalescingWindow: nil)

        let external = makeSnapshot("external")
        _ = history.reconcileWithRefresh(external)
        #expect(history.lastInvalidationReason == .externalFileChange)

        let next = makeSnapshot("next")
        history.recordChange(from: external, to: next, coalescingWindow: nil)
        #expect(history.lastInvalidationReason == nil)
    }

    @Test func `redo stack pruning respects maxUndoSteps`() {
        let initial = makeSnapshot("v0")
        let history = BufferEditHistory(initial: initial)
        history.maxUndoSteps = 3

        var prev = initial
        for i in 1 ... 5 {
            let next = makeSnapshot("v\(i)")
            history.recordChange(from: prev, to: next, coalescingWindow: nil)
            prev = next
        }

        // Undo all — redo stack should be capped at 3
        var current = prev
        while case .applied(let snapshot) = history.undo(current: current) {
            current = snapshot
        }

        var redoCount = 0
        while case .applied(let snapshot) = history.redo(current: current) {
            redoCount += 1
            current = snapshot
        }
        #expect(redoCount == 3)
    }

    @Test @MainActor func `config maxUndoSteps wires through DocumentBuffer`() {
        let buffer = DocumentBuffer(
            filePath: "/tmp/test.txt",
            fileName: "test.txt",
            content: "hello",
            language: nil,
            maxUndoSteps: 5
        )
        #expect(buffer.editHistory.maxUndoSteps == 5)
    }

    /// Audit A2c — snapshots that enter the undo stack must not retain the
    /// rope's materialised `text` / `lines` caches. A warm snapshot pinning
    /// multi-megabyte cached strings × 200 transitions × N buffers was the
    /// proximate cause of the ~1 GB long-session drift before the cache-drop
    /// at record time landed.
    @Test func `recordChange drops snapshot text and lines caches`() {
        let initial = makeSnapshot("alpha\nbeta\ngamma")
        let after = makeSnapshot("alpha\nbeta\ngamma\ndelta")

        // Warm both snapshots' caches BEFORE recordChange so we can verify
        // the cache-drop took effect.
        _ = initial.textBuffer.text
        _ = initial.textBuffer.lines
        _ = after.textBuffer.text
        _ = after.textBuffer.lines
        #expect(!initial.textBuffer._testSnapshotCachesAreEmpty)
        #expect(!after.textBuffer._testSnapshotCachesAreEmpty)

        let history = BufferEditHistory(initial: initial)
        history.recordChange(from: initial, to: after, coalescingWindow: nil)

        guard let top = history._testTopOfUndoStack else {
            Issue.record("Expected a transition on top of the undo stack")
            return
        }
        // The retained copies inside the undo stack carry empty caches.
        #expect(top.before.textBuffer._testSnapshotCachesAreEmpty)
        #expect(top.after.textBuffer._testSnapshotCachesAreEmpty)
        // Content still intact and recomputable on demand.
        #expect(top.before.textBuffer.text == "alpha\nbeta\ngamma")
        #expect(top.after.textBuffer.text == "alpha\nbeta\ngamma\ndelta")
    }

    /// The coalescing path overwrites the trailing transition's `after`
    /// snapshot. That new `after` must also have its caches dropped.
    @Test func `recordChange drops caches on the coalesced after snapshot`() {
        let initial = makeSnapshot("alpha")
        let mid = makeSnapshot("alphabeta")
        let final = makeSnapshot("alphabetagamma")

        let history = BufferEditHistory(initial: initial)
        history.recordChange(from: initial, to: mid, coalescingWindow: nil)

        // Warm the final snapshot's caches, then coalesce.
        _ = final.textBuffer.text
        _ = final.textBuffer.lines
        history.recordChange(from: mid, to: final, coalescingWindow: 10)

        guard let top = history._testTopOfUndoStack else {
            Issue.record("Expected a transition")
            return
        }
        #expect(top.after.textBuffer._testSnapshotCachesAreEmpty)
        #expect(top.after.textBuffer.text == "alphabetagamma")
    }

    /// Audit A2a — count-based `maxUndoSteps` doesn't bound memory; a
    /// 1 MB document × 200 entries is 400 MB regardless of count. The new
    /// `maxUndoBytes` cap prunes oldest entries until total retained
    /// snapshot bytes fall under the byte budget.
    @Test func `recordChange prunes by byte budget when document is large`() {
        // Use a small budget so we don't have to allocate hundreds of MB.
        let initial = makeSnapshot(String(repeating: "x", count: 1_000))
        let history = BufferEditHistory(initial: initial)
        history.maxUndoBytes = 32 * 1024  // 32 KB budget for this test

        // Each transition retains ~2 × 4 KB = ~8 KB. Record 20 of them.
        var previous = initial
        for index in 0 ..< 20 {
            let next = makeSnapshot(String(repeating: "x", count: 4_000 + index))
            history.recordChange(from: previous, to: next, coalescingWindow: nil)
            previous = next
        }

        let retained = history._testTotalUndoBytes
        #expect(
            retained <= history.maxUndoBytes,
            "retained bytes \(retained) must be at most maxUndoBytes \(history.maxUndoBytes)"
        )
        // Count cap not in play; budget cap should have done the pruning.
        // Sanity: we recorded 20 but expect far fewer to remain.
        if let top = history._testTopOfUndoStack {
            // Most recent transition still on top (count > 0).
            #expect(top.after.textBuffer.byteCount > 0)
        }
    }

    /// Confirm the byte cap doesn't drop the only remaining transition
    /// even when a single transition exceeds the budget. The user should
    /// always have at least one step of undo.
    @Test func `recordChange retains one transition even past byte budget`() {
        let initial = makeSnapshot("short")
        let history = BufferEditHistory(initial: initial)
        history.maxUndoBytes = 100  // absurdly small

        let huge = makeSnapshot(String(repeating: "y", count: 10_000))
        history.recordChange(from: initial, to: huge, coalescingWindow: nil)

        #expect(history.hasUndo, "the single transition must survive even past budget")
    }
}
