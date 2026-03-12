import KittyText
import Testing

@testable import KittyWorkspace

@Suite
struct WorkspaceTests {
    @Test
    func workspaceTargetCompiles() {
        // Placeholder — verifies the target links correctly
    }
}

// MARK: - BufferEditHistoryTests

@Suite struct BufferEditHistoryTests {
    private func makeSnapshot(_ text: String) -> BufferEditSnapshot {
        BufferEditSnapshot(
            textBuffer: TextBuffer(text),
            textCursor: TextCursor(),
            lineEnding: .lf
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
}
