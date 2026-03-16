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

extension FileTreeOperation {
    var affectedPaths: Set<String> {
        switch self {
        case .create(let snapshot), .delete(let snapshot), .duplicate(let snapshot):
            return snapshot.allPaths
        case .move(let sourcePath, let destinationPath):
            return [sourcePath, destinationPath]
        }
    }

    var humanDescription: String {
        switch self {
        case .create(let snapshot):
            return "Create \(snapshot.displayName)"
        case .delete(let snapshot):
            return "Delete \(snapshot.displayName)"
        case .move(let sourcePath, let destinationPath):
            let from = URL(fileURLWithPath: sourcePath).lastPathComponent
            let to = URL(fileURLWithPath: destinationPath).lastPathComponent
            return from == to ? "Move \(to)" : "Rename \(from) → \(to)"
        case .duplicate(let snapshot):
            return "Duplicate \(snapshot.displayName)"
        }
    }
}

extension FileSystemSnapshot {
    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var allPaths: Set<String> {
        var result = Set<String>()
        collectPaths(into: &result)
        return result
    }

    private func collectPaths(into result: inout Set<String>) {
        result.insert(path)
        if case .directory(_, let children) = self {
            for child in children {
                child.collectPaths(into: &result)
            }
        }
    }
}

struct FileTreeOperationRecord: Sendable {
    let operation: FileTreeOperation
    let affectedPaths: Set<String>
    let description: String
    let undoSelectionPath: String
    let redoSelectionPath: String
}

final class FileTreeOperationHistory {
    enum StepResult {
        case applied(FileTreeOperationRecord)
        case unavailable
        case invalidated
    }

    enum InvalidationReason {
        case externalFileChange
        case pathSetMismatch
    }

    private var undoStack: [FileTreeOperationRecord] = []
    private var redoStack: [FileTreeOperationRecord] = []
    private var currentPathSet: Set<String>?
    private(set) var lastInvalidationReason: InvalidationReason?
    var maxOperationSteps: Int = 50

    var hasUndo: Bool {
        !undoStack.isEmpty
    }

    var hasRedo: Bool {
        !redoStack.isEmpty
    }

    var peekUndo: FileTreeOperationRecord? {
        undoStack.last
    }

    var peekRedo: FileTreeOperationRecord? {
        redoStack.last
    }

    func validateRefresh(with nodes: [FileNode]) -> Bool {
        let newPathSet = Self.collectAllPaths(from: nodes)
        defer { currentPathSet = newPathSet }

        guard let oldPathSet = currentPathSet else { return false }
        guard oldPathSet != newPathSet else { return false }
        guard !undoStack.isEmpty || !redoStack.isEmpty else { return false }

        let changedPaths = oldPathSet.symmetricDifference(newPathSet)
        var didInvalidate = false

        if let cutIndex = undoStack.firstIndex(where: { !$0.affectedPaths.isDisjoint(with: changedPaths) }) {
            undoStack.removeSubrange(cutIndex...)
            didInvalidate = true
        }

        if let cutIndex = redoStack.firstIndex(where: { !$0.affectedPaths.isDisjoint(with: changedPaths) }) {
            redoStack.removeSubrange(cutIndex...)
            didInvalidate = true
        }

        if didInvalidate {
            lastInvalidationReason = .externalFileChange
        }
        return didInvalidate
    }

    func record(
        _ operation: FileTreeOperation,
        undoSelectionPath: String,
        redoSelectionPath: String,
        currentNodes: [FileNode]
    ) {
        let record = FileTreeOperationRecord(
            operation: operation,
            affectedPaths: operation.affectedPaths,
            description: operation.humanDescription,
            undoSelectionPath: undoSelectionPath,
            redoSelectionPath: redoSelectionPath
        )
        undoStack.append(record)
        if undoStack.count > maxOperationSteps {
            undoStack.removeFirst(undoStack.count - maxOperationSteps)
        }
        redoStack.removeAll(keepingCapacity: true)
        currentPathSet = Self.collectAllPaths(from: currentNodes)
    }

    func undo(currentNodes: [FileNode]) -> StepResult {
        guard matchesCurrent(nodes: currentNodes) else {
            invalidate(currentNodes: currentNodes)
            return .invalidated
        }
        guard let record = undoStack.popLast() else {
            return .unavailable
        }

        redoStack.append(record)
        if redoStack.count > maxOperationSteps {
            redoStack.removeFirst(redoStack.count - maxOperationSteps)
        }
        return .applied(record)
    }

    func redo(currentNodes: [FileNode]) -> StepResult {
        guard matchesCurrent(nodes: currentNodes) else {
            invalidate(currentNodes: currentNodes)
            return .invalidated
        }
        guard let record = redoStack.popLast() else {
            return .unavailable
        }

        undoStack.append(record)
        if undoStack.count > maxOperationSteps {
            undoStack.removeFirst(undoStack.count - maxOperationSteps)
        }
        return .applied(record)
    }

    func updateCurrent(nodes: [FileNode]) {
        currentPathSet = Self.collectAllPaths(from: nodes)
    }

    func clear(currentNodes: [FileNode]) {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        currentPathSet = Self.collectAllPaths(from: currentNodes)
    }

    private func invalidate(currentNodes: [FileNode]) {
        clear(currentNodes: currentNodes)
    }

    private func matchesCurrent(nodes: [FileNode]) -> Bool {
        let pathSet = Self.collectAllPaths(from: nodes)
        guard let currentPathSet else {
            self.currentPathSet = pathSet
            return true
        }
        return pathSet == currentPathSet
    }

    static func collectAllPaths(from nodes: [FileNode]) -> Set<String> {
        var result = Set<String>()
        collectPaths(nodes, into: &result)
        return result
    }

    private static func collectPaths(_ nodes: [FileNode], into result: inout Set<String>) {
        for node in nodes {
            result.insert(node.path)
            collectPaths(node.children, into: &result)
        }
    }
}
