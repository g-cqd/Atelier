public import AtelierText
import KittyFileTree

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
        // Memoized on the rope storage: the full-content cost is paid once per mutation.
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
        var recordedAt: ClockInstant
    }

    private let clock: any Clock<Duration>
    private var undoStack: [Transition] = []
    private var redoStack: [Transition] = []
    private var currentFingerprint: Int
    private var savedFingerprint: Int
    public var maxUndoSteps: Int = 200
    /// The snapshot bytes each of the undo and redo stacks may retain, both sides of a transition counted: past it
    /// the oldest entries are pruned, the newest always kept. `maxUndoSteps` caps the entry count as well.
    public var maxUndoBytes: Int = 32 * 1024 * 1024
    public private(set) var lastInvalidationReason: InvalidationReason?

    public init(initial snapshot: BufferEditSnapshot, clock: any Clock<Duration> = ContinuousClock()) {
        let fingerprint = snapshot.contentFingerprint
        self.currentFingerprint = fingerprint
        self.savedFingerprint = fingerprint
        self.clock = clock
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
        coalescingWindow: Duration?
    ) {
        let beforeFingerprint = before.contentFingerprint
        let afterFingerprint = after.contentFingerprint
        currentFingerprint = afterFingerprint
        lastInvalidationReason = nil

        guard beforeFingerprint != afterFingerprint else { return }

        // Stored without their rope's text and line caches, which would pin megabytes per retained transition.
        let recordedBefore = Self.snapshotForStorage(before)
        let recordedAfter = Self.snapshotForStorage(after)

        let recordedAt = clock.erasedNow()
        if let coalescingWindow,
            coalescingWindow > .zero,
            redoStack.isEmpty,
            let lastIndex = undoStack.indices.last,
            undoStack[lastIndex].recordedAt.duration(to: recordedAt) <= coalescingWindow,
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

    /// Drops the oldest undo entries until both `maxUndoSteps` and `maxUndoBytes` hold.
    private func enforceUndoRetentionCaps() {
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
        while undoStack.count > 1, retainedBytes(in: undoStack) > maxUndoBytes {
            undoStack.removeFirst()
        }
    }

    /// Drops the oldest redo entries until both `maxUndoSteps` and `maxUndoBytes` hold.
    private func enforceRedoRetentionCaps() {
        if redoStack.count > maxUndoSteps {
            redoStack.removeFirst(redoStack.count - maxUndoSteps)
        }
        while redoStack.count > 1, retainedBytes(in: redoStack) > maxUndoBytes {
            redoStack.removeFirst()
        }
    }

    /// The `before` and `after` byte counts summed over `stack`, O(1) per transition as `Rope.byteCount` is cached.
    private func retainedBytes(in stack: [Transition]) -> Int {
        var total = 0
        for transition in stack {
            total += transition.before.textBuffer.byteCount
            total += transition.after.textBuffer.byteCount
        }
        return total
    }

    /// Test probe: the snapshot bytes the undo stack retains.
    var _testTotalUndoBytes: Int {
        retainedBytes(in: undoStack)
    }

    /// Test probe: the snapshot bytes the redo stack retains.
    var _testTotalRedoBytes: Int {
        retainedBytes(in: redoStack)
    }

    private static func snapshotForStorage(_ snapshot: BufferEditSnapshot) -> BufferEditSnapshot {
        var copy = snapshot
        copy.textBuffer.invalidateSnapshotCaches()
        return copy
    }

    /// Test probe: the snapshots of the latest undo transition.
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
