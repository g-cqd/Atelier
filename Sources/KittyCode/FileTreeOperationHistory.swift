import Foundation
import KittyFileTree

indirect enum FileSystemSnapshot: Sendable {
    case file(path: String, data: Data)
    case directory(path: String, children: [FileSystemSnapshot])

    var path: String {
        switch self {
        case .file(let path, _):
            return path
        case .directory(let path, _):
            return path
        }
    }
}

enum FileTreeOperation: Sendable {
    case create(snapshot: FileSystemSnapshot)
    case delete(snapshot: FileSystemSnapshot)
    case move(sourcePath: String, destinationPath: String)
    case duplicate(snapshot: FileSystemSnapshot)
}

final class FileTreeOperationHistory {
    enum StepResult {
        case applied(FileTreeOperation)
        case unavailable
        case invalidated
    }

    private var undoStack: [FileTreeOperation] = []
    private var redoStack: [FileTreeOperation] = []
    private var currentFingerprint: Int?

    var hasUndo: Bool {
        !undoStack.isEmpty
    }

    var hasRedo: Bool {
        !redoStack.isEmpty
    }

    func validateRefresh(with nodes: [FileNode]) -> Bool {
        let fingerprint = Self.fingerprint(for: nodes)
        defer { currentFingerprint = fingerprint }

        guard let currentFingerprint else { return false }
        let invalidated =
            fingerprint != currentFingerprint && (!undoStack.isEmpty || !redoStack.isEmpty)
        if invalidated {
            undoStack.removeAll(keepingCapacity: true)
            redoStack.removeAll(keepingCapacity: true)
        }
        return invalidated
    }

    func record(_ operation: FileTreeOperation, currentNodes: [FileNode]) {
        undoStack.append(operation)
        redoStack.removeAll(keepingCapacity: true)
        currentFingerprint = Self.fingerprint(for: currentNodes)
    }

    func undo(currentNodes: [FileNode]) -> StepResult {
        guard matchesCurrent(nodes: currentNodes) else {
            invalidate(currentNodes: currentNodes)
            return .invalidated
        }
        guard let operation = undoStack.popLast() else {
            return .unavailable
        }

        redoStack.append(operation)
        return .applied(operation)
    }

    func redo(currentNodes: [FileNode]) -> StepResult {
        guard matchesCurrent(nodes: currentNodes) else {
            invalidate(currentNodes: currentNodes)
            return .invalidated
        }
        guard let operation = redoStack.popLast() else {
            return .unavailable
        }

        undoStack.append(operation)
        return .applied(operation)
    }

    func updateCurrent(nodes: [FileNode]) {
        currentFingerprint = Self.fingerprint(for: nodes)
    }

    func clear(currentNodes: [FileNode]) {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        currentFingerprint = Self.fingerprint(for: currentNodes)
    }

    private func invalidate(currentNodes: [FileNode]) {
        clear(currentNodes: currentNodes)
    }

    private func matchesCurrent(nodes: [FileNode]) -> Bool {
        let fingerprint = Self.fingerprint(for: nodes)
        guard let currentFingerprint else {
            self.currentFingerprint = fingerprint
            return true
        }
        return fingerprint == currentFingerprint
    }

    private static func fingerprint(for nodes: [FileNode]) -> Int {
        var hasher = Hasher()
        hasher.combine(nodes.count)
        fingerprint(nodes, into: &hasher)
        return hasher.finalize()
    }

    private static func fingerprint(_ nodes: [FileNode], into hasher: inout Hasher) {
        for node in nodes {
            hasher.combine(node.path)
            hasher.combine(node.isDirectory)
            hasher.combine(node.children.count)
            fingerprint(node.children, into: &hasher)
        }
    }
}
