import Foundation
import KittyText

public struct BufferEditSnapshot: Sendable {
    public var textBuffer: TextBuffer
    public var textCursor: TextCursor
    public var lineEnding: TextDocument.LineEnding

    public init(
        textBuffer: TextBuffer,
        textCursor: TextCursor,
        lineEnding: TextDocument.LineEnding
    ) {
        self.textBuffer = textBuffer
        self.textCursor = textCursor
        self.lineEnding = lineEnding
    }

    public var contentFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(lineEnding.rawValue)
        hasher.combine(textBuffer.lineCount)
        for line in textBuffer.lines {
            hasher.combine(line)
        }
        return hasher.finalize()
    }
}

public final class BufferEditHistory {
    public enum StepResult {
        case applied(BufferEditSnapshot)
        case unavailable
        case invalidated
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

    public func recordChange(
        from before: BufferEditSnapshot,
        to after: BufferEditSnapshot,
        coalescingWindow: TimeInterval?
    ) {
        let beforeFingerprint = before.contentFingerprint
        let afterFingerprint = after.contentFingerprint
        currentFingerprint = afterFingerprint

        guard beforeFingerprint != afterFingerprint else { return }

        let recordedAt = Date()
        if let coalescingWindow,
           coalescingWindow > 0,
           redoStack.isEmpty,
           let lastIndex = undoStack.indices.last,
           recordedAt.timeIntervalSince(undoStack[lastIndex].recordedAt) <= coalescingWindow
        {
            undoStack[lastIndex].after = after
            undoStack[lastIndex].recordedAt = recordedAt
            return
        }

        undoStack.append(Transition(before: before, after: after, recordedAt: recordedAt))
        redoStack.removeAll(keepingCapacity: true)
    }

    public func undo(current snapshot: BufferEditSnapshot) -> StepResult {
        guard snapshot.contentFingerprint == currentFingerprint else {
            reset(to: snapshot, marksSaved: false)
            return .invalidated
        }
        guard let transition = undoStack.popLast() else {
            return .unavailable
        }

        redoStack.append(transition)
        currentFingerprint = transition.before.contentFingerprint
        return .applied(transition.before)
    }

    public func redo(current snapshot: BufferEditSnapshot) -> StepResult {
        guard snapshot.contentFingerprint == currentFingerprint else {
            reset(to: snapshot, marksSaved: false)
            return .invalidated
        }
        guard let transition = redoStack.popLast() else {
            return .unavailable
        }

        undoStack.append(transition)
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
        let invalidated = fingerprint != currentFingerprint && (!undoStack.isEmpty || !redoStack.isEmpty)
        currentFingerprint = fingerprint
        savedFingerprint = fingerprint
        if invalidated {
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
