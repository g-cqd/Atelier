public import Foundation
public import KittyFileTree

public indirect enum FileSystemSnapshot: Sendable {
    case file(path: String, data: Data)
    case directory(path: String, children: [FileSystemSnapshot])

    public var path: String {
        switch self {
        case .file(let path, _):
            return path
        case .directory(let path, _):
            return path
        }
    }
}

public enum FileTreeOperation: Sendable {
    case create(snapshot: FileSystemSnapshot)
    case delete(snapshot: FileSystemSnapshot)
    case move(sourcePath: String, destinationPath: String)
    case duplicate(snapshot: FileSystemSnapshot)
}

extension FileTreeOperation {
    public var affectedPaths: Set<String> {
        switch self {
        case .create(let snapshot), .delete(let snapshot), .duplicate(let snapshot):
            return snapshot.allPaths
        case .move(let sourcePath, let destinationPath):
            return [sourcePath, destinationPath]
        }
    }

    public var humanDescription: String {
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
    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public var allPaths: Set<String> {
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

public struct FileTreeOperationRecord: Sendable {
    public let operation: FileTreeOperation
    public let affectedPaths: Set<String>
    public let description: String
    public let undoSelectionPath: String
    public let redoSelectionPath: String
}

public final class FileTreeOperationHistory {
    public enum StepResult {
        case applied(FileTreeOperationRecord)
        case unavailable
        case invalidated
    }

    public enum InvalidationReason {
        case externalFileChange
        case pathSetMismatch
    }

    private var undoStack: [FileTreeOperationRecord] = []
    private var redoStack: [FileTreeOperationRecord] = []
    private var currentPathSet: Set<String>?
    private(set) var lastInvalidationReason: InvalidationReason?
    public var maxOperationSteps: Int = 50

    public var hasUndo: Bool {
        !undoStack.isEmpty
    }

    public var hasRedo: Bool {
        !redoStack.isEmpty
    }

    public var peekUndo: FileTreeOperationRecord? {
        undoStack.last
    }

    public var peekRedo: FileTreeOperationRecord? {
        redoStack.last
    }

    public func validateRefresh(with nodes: [FileNode]) -> Bool {
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

    public func record(
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

    public func undo(currentNodes: [FileNode]) -> StepResult {
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

    public func redo(currentNodes: [FileNode]) -> StepResult {
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

    public func updateCurrent(nodes: [FileNode]) {
        currentPathSet = Self.collectAllPaths(from: nodes)
    }

    public func clear(currentNodes: [FileNode]) {
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

    public static func collectAllPaths(from nodes: [FileNode]) -> Set<String> {
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
