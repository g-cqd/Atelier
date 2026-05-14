import Foundation
import KittyText

public struct BufferEditSnapshot: Sendable {
    public var textBuffer: TextBuffer
    public var textCursor: TextCursor
    public var lineEnding: TextDocument.LineEnding
    public var selection: TextSelection?

    public init(
        textBuffer: TextBuffer,
        textCursor: TextCursor,
        lineEnding: TextDocument.LineEnding,
        selection: TextSelection? = nil
    ) {
        self.textBuffer = textBuffer
        self.textCursor = textCursor
        self.lineEnding = lineEnding
        self.selection = selection
    }

    public var contentFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(lineEnding.rawValue)
        // `textBuffer.contentHash` is memoized on the rope storage; it stays
        // O(1) across repeated reads of the same buffer state and only pays
        // the full-content cost once per mutation.
        hasher.combine(textBuffer.contentHash)
        return hasher.finalize()
    }
}

public final class BufferEditHistory {
    public enum StepResult {
        case applied(BufferEditSnapshot)
        case unavailable
        case invalidated
    }

    public enum InvalidationReason: Sendable {
        case externalFileChange
        case fingerprintMismatch
    }

    private struct Transition {
        var before: BufferEditSnapshot
        var after: BufferEditSnapshot
        var recordedAt: Date
    }

    private var undoStack: [Transition] = []
    private var redoStack: [Transition] = []
    private var currentFingerprint: Int
    private var savedFingerprint: Int
    public var maxUndoSteps: Int = 200
    /// Soft retention cap for undo + redo stacks combined, in bytes. After
    /// each `recordChange` (and `undo` / `redo` shuffle), the oldest entries
    /// are pruned until total retained snapshot bytes fall under this limit.
    /// Defaults to 32 MB — keeps a multi-MB-file editing session bounded
    /// while leaving headroom for ~30 transitions on a 1 MB document. The
    /// count cap (`maxUndoSteps`) still applies as a secondary guard
    /// against many small transitions exhausting metadata overhead.
    public var maxUndoBytes: Int = 32 * 1024 * 1024
    public private(set) var lastInvalidationReason: InvalidationReason?

    public init(initial snapshot: BufferEditSnapshot) {
        let fingerprint = snapshot.contentFingerprint
        self.currentFingerprint = fingerprint
        self.savedFingerprint = fingerprint
    }

    public var hasUndo: Bool {
        !undoStack.isEmpty
    }

    public var hasRedo: Bool {
        !redoStack.isEmpty
    }

    public var isNextUndoAtSaveBoundary: Bool {
        guard let transition = undoStack.last else { return false }
        return transition.before.contentFingerprint == savedFingerprint
    }

    public func recordChange(
        from before: BufferEditSnapshot,
        to after: BufferEditSnapshot,
        coalescingWindow: TimeInterval?
    ) {
        let beforeFingerprint = before.contentFingerprint
        let afterFingerprint = after.contentFingerprint
        currentFingerprint = afterFingerprint
        lastInvalidationReason = nil

        guard beforeFingerprint != afterFingerprint else { return }

        // Drop the snapshots' rope materialisation caches before they enter
        // the undo stack. Without this, every retained transition pins a
        // `cachedText` (full document `String`) and a `cachedLines`
        // (`[String]` of every line) on its prior rope storage — multi-MB
        // per snapshot on a 1 MB document, which accumulates linearly with
        // history depth. Reads on the live buffer recompute on demand.
        let recordedBefore = Self.snapshotForStorage(before)
        let recordedAfter = Self.snapshotForStorage(after)

        let recordedAt = Date()
        if let coalescingWindow,
            coalescingWindow > 0,
            redoStack.isEmpty,
            let lastIndex = undoStack.indices.last,
            recordedAt.timeIntervalSince(undoStack[lastIndex].recordedAt) <= coalescingWindow,
            before.textCursor.row == undoStack[lastIndex].after.textCursor.row,
            before.textCursor.col == undoStack[lastIndex].after.textCursor.col
        {
            undoStack[lastIndex].after = recordedAfter
            undoStack[lastIndex].recordedAt = recordedAt
            return
        }

        undoStack.append(
            Transition(before: recordedBefore, after: recordedAfter, recordedAt: recordedAt))
        redoStack.removeAll(keepingCapacity: true)

        enforceUndoRetentionCaps()
    }

    /// Drops oldest entries from `undoStack` until BOTH the count cap
    /// (`maxUndoSteps`) and the byte cap (`maxUndoBytes`) are satisfied.
    /// The byte cap is the real memory guard: count alone can't bound
    /// retention when a single transition holds two snapshots of a
    /// multi-MB document.
    private func enforceUndoRetentionCaps() {
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
        while undoStack.count > 1, retainedBytes(in: undoStack) > maxUndoBytes {
            undoStack.removeFirst()
        }
    }

    /// Mirror of `enforceUndoRetentionCaps` for the redo stack. The total
    /// retention worst case is therefore `2 * maxUndoBytes` (64 MB by
    /// default) — still bounded and small compared to the prior unbounded
    /// retention.
    private func enforceRedoRetentionCaps() {
        if redoStack.count > maxUndoSteps {
            redoStack.removeFirst(redoStack.count - maxUndoSteps)
        }
        while redoStack.count > 1, retainedBytes(in: redoStack) > maxUndoBytes {
            redoStack.removeFirst()
        }
    }

    /// Sum of `before` + `after` document byte counts across the given
    /// transition list. O(1) per snapshot since `Rope.byteCount` is cached
    /// on the tree's root.
    private func retainedBytes(in stack: [Transition]) -> Int {
        var total = 0
        for transition in stack {
            total += transition.before.textBuffer.byteCount
            total += transition.after.textBuffer.byteCount
        }
        return total
    }

    /// Test-only probe — current total retained bytes across the undo
    /// stack. Pinned by `BufferEditHistoryTests.byteBudgetEnforced`.
    var _testTotalUndoBytes: Int {
        retainedBytes(in: undoStack)
    }

    /// Test-only probe — same for redo stack.
    var _testTotalRedoBytes: Int {
        retainedBytes(in: redoStack)
    }

    private static func snapshotForStorage(_ snapshot: BufferEditSnapshot) -> BufferEditSnapshot {
        var copy = snapshot
        copy.textBuffer.invalidateSnapshotCaches()
        return copy
    }

    /// Test-only probe — returns the most recently recorded undo transition's
    /// `before`/`after` snapshots. Used by `BufferEditHistoryTests` to pin
    /// the cache-drop invariant of `recordChange`.
    var _testTopOfUndoStack: (before: BufferEditSnapshot, after: BufferEditSnapshot)? {
        undoStack.last.map { ($0.before, $0.after) }
    }

    public func undo(current snapshot: BufferEditSnapshot) -> StepResult {
        guard snapshot.contentFingerprint == currentFingerprint else {
            lastInvalidationReason = .fingerprintMismatch
            reset(to: snapshot, marksSaved: false)
            return .invalidated
        }
        guard let transition = undoStack.popLast() else {
            return .unavailable
        }

        redoStack.append(transition)
        enforceRedoRetentionCaps()
        currentFingerprint = transition.before.contentFingerprint
        return .applied(transition.before)
    }

    public func redo(current snapshot: BufferEditSnapshot) -> StepResult {
        guard snapshot.contentFingerprint == currentFingerprint else {
            lastInvalidationReason = .fingerprintMismatch
            reset(to: snapshot, marksSaved: false)
            return .invalidated
        }
        guard let transition = redoStack.popLast() else {
            return .unavailable
        }

        undoStack.append(transition)
        enforceUndoRetentionCaps()
        currentFingerprint = transition.after.contentFingerprint
        return .applied(transition.after)
    }

    public func markSaved(_ snapshot: BufferEditSnapshot) {
        let fingerprint = snapshot.contentFingerprint
        currentFingerprint = fingerprint
        savedFingerprint = fingerprint
    }

    public func isDirty(current snapshot: BufferEditSnapshot) -> Bool {
        snapshot.contentFingerprint != savedFingerprint
    }

    @discardableResult
    public func reconcileWithRefresh(_ snapshot: BufferEditSnapshot) -> Bool {
        let fingerprint = snapshot.contentFingerprint
        let invalidated =
            fingerprint != currentFingerprint && (!undoStack.isEmpty || !redoStack.isEmpty)
        currentFingerprint = fingerprint
        savedFingerprint = fingerprint
        if invalidated {
            lastInvalidationReason = .externalFileChange
            undoStack.removeAll(keepingCapacity: true)
            redoStack.removeAll(keepingCapacity: true)
        }
        return invalidated
    }

    public func reset(to snapshot: BufferEditSnapshot, marksSaved: Bool = true) {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        currentFingerprint = snapshot.contentFingerprint
        if marksSaved {
            savedFingerprint = currentFingerprint
        }
    }
}
