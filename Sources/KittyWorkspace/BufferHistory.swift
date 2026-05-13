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

        let recordedAt = Date()
        if let coalescingWindow,
            coalescingWindow > 0,
            redoStack.isEmpty,
            let lastIndex = undoStack.indices.last,
            recordedAt.timeIntervalSince(undoStack[lastIndex].recordedAt) <= coalescingWindow,
            before.textCursor.row == undoStack[lastIndex].after.textCursor.row,
            before.textCursor.col == undoStack[lastIndex].after.textCursor.col
        {
            undoStack[lastIndex].after = after
            undoStack[lastIndex].recordedAt = recordedAt
            return
        }

        undoStack.append(Transition(before: before, after: after, recordedAt: recordedAt))
        redoStack.removeAll(keepingCapacity: true)

        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
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
        if redoStack.count > maxUndoSteps {
            redoStack.removeFirst(redoStack.count - maxUndoSteps)
        }
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
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst(undoStack.count - maxUndoSteps)
        }
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
