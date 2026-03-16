import Foundation
import KittyFileTree

extension EditorState {
    @discardableResult
    func createTreeFile(at destinationPath: String, suggestedDirectory _: String) async -> Bool {
        guard validateCreatablePath(destinationPath) else { return false }

        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parentPath = destinationURL.deletingLastPathComponent().path
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            guard FileManager.default.createFile(atPath: destinationPath, contents: Data()) else {
                statusMessage = "Failed to create file"
                return false
            }

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            fileTreeHistory.record(
                .create(snapshot: .file(path: destinationPath, data: Data())),
                undoSelectionPath: parentPath,
                redoSelectionPath: destinationPath,
                currentNodes: treeNodes)
            statusMessage = "Created \(destinationURL.lastPathComponent)"
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error creating file: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func createTreeDirectory(at destinationPath: String, suggestedDirectory _: String) async -> Bool
    {
        guard validateCreatablePath(destinationPath) else { return false }

        let parentPath = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: destinationPath),
                withIntermediateDirectories: true,
                attributes: nil
            )

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            fileTreeHistory.record(
                .create(snapshot: .directory(path: destinationPath, children: [])),
                undoSelectionPath: parentPath,
                redoSelectionPath: destinationPath,
                currentNodes: treeNodes)
            statusMessage = "Created \(URL(fileURLWithPath: destinationPath).lastPathComponent)"
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error creating folder: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func renameTreeItem(from sourcePath: String, to destinationPath: String) async -> Bool {
        await moveTreeItem(from: sourcePath, to: destinationPath)
    }

    @discardableResult
    func moveTreeItem(from sourcePath: String, to destinationPath: String) async -> Bool {
        guard validateMovablePath(sourcePath, destinationPath: destinationPath) else {
            return false
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            fileTreeHistory.record(
                .move(sourcePath: sourcePath, destinationPath: destinationPath),
                undoSelectionPath: sourcePath,
                redoSelectionPath: destinationPath,
                currentNodes: treeNodes
            )
            statusMessage = "Moved \(destinationURL.lastPathComponent)"
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error moving item: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func duplicateTreeItem(at sourcePath: String, to destinationPath: String) async -> Bool {
        guard validateCreatablePath(destinationPath) else { return false }
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            statusMessage = "Missing source item"
            return false
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parentPath = destinationURL.deletingLastPathComponent().path
        let displayName = destinationURL.lastPathComponent
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
            let snapshot = captureFileSystemSnapshotIfReasonable(at: destinationPath)

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            if let snapshot {
                fileTreeHistory.record(
                    .duplicate(snapshot: snapshot),
                    undoSelectionPath: parentPath,
                    redoSelectionPath: destinationPath,
                    currentNodes: treeNodes)
                statusMessage = "Duplicated \(displayName)"
            } else {
                fileTreeHistory.updateCurrent(nodes: treeNodes)
                statusMessage = "Duplicated \(displayName) (too large for undo)"
            }
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error duplicating item: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteTreeItem(at path: String) async -> Bool {
        guard validateDeletablePath(path) else { return false }

        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let displayName = URL(fileURLWithPath: path).lastPathComponent
        do {
            let snapshot = captureFileSystemSnapshotIfReasonable(at: path)
            try FileManager.default.removeItem(atPath: path)

            await loadInitialTree(validateHistory: false)
            selectTreePath(parentPath)
            if let snapshot {
                fileTreeHistory.record(
                    .delete(snapshot: snapshot),
                    undoSelectionPath: snapshot.path,
                    redoSelectionPath: parentPath,
                    currentNodes: treeNodes)
                statusMessage = "Deleted \(displayName)"
            } else {
                fileTreeHistory.updateCurrent(nodes: treeNodes)
                statusMessage = "Deleted \(displayName) (too large for undo)"
            }
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error deleting item: \(error.localizedDescription)"
            return false
        }
    }

    func undoFileTreeOperation() async {
        switch fileTreeHistory.undo(currentNodes: treeNodes) {
        case .applied(let record):
            let success = await applyUndo(record)
            if success {
                statusMessage = "Undo: \(record.description)"
            } else {
                fileTreeHistory.clear(currentNodes: treeNodes)
            }
        case .unavailable:
            statusMessage = "Nothing to undo"
        case .invalidated:
            statusMessage = "File history cleared after tree refresh"
        }
    }

    func redoFileTreeOperation() async {
        switch fileTreeHistory.redo(currentNodes: treeNodes) {
        case .applied(let record):
            let success = await applyRedo(record)
            if success {
                statusMessage = "Redo: \(record.description)"
            } else {
                fileTreeHistory.clear(currentNodes: treeNodes)
            }
        case .unavailable:
            statusMessage = "Nothing to redo"
        case .invalidated:
            statusMessage = "File history cleared after tree refresh"
        }
    }

    private func applyUndo(_ record: FileTreeOperationRecord) async -> Bool {
        do {
            switch record.operation {
            case .create(let snapshot):
                try removeItemIfExists(at: snapshot.path)
            case .delete(let snapshot):
                try restore(snapshot: snapshot)
            case .move(let sourcePath, let destinationPath):
                try FileManager.default.moveItem(atPath: destinationPath, toPath: sourcePath)
            case .duplicate(let snapshot):
                try removeItemIfExists(at: snapshot.path)
            }

            await loadInitialTree(validateHistory: false)
            selectTreePath(record.undoSelectionPath)
            fileTreeHistory.updateCurrent(nodes: treeNodes)
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error undoing file operation: \(error.localizedDescription)"
            return false
        }
    }

    private func applyRedo(_ record: FileTreeOperationRecord) async -> Bool {
        do {
            switch record.operation {
            case .create(let snapshot), .duplicate(let snapshot):
                try restore(snapshot: snapshot)
            case .delete(let snapshot):
                try removeItemIfExists(at: snapshot.path)
            case .move(let sourcePath, let destinationPath):
                try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
            }

            await loadInitialTree(validateHistory: false)
            selectTreePath(record.redoSelectionPath)
            fileTreeHistory.updateCurrent(nodes: treeNodes)
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error redoing file operation: \(error.localizedDescription)"
            return false
        }
    }

    private func validateCreatablePath(_ path: String) -> Bool {
        guard SecurePath.isValid(path, root: rootPath) else {
            statusMessage = "Access denied: path outside project root"
            return false
        }
        guard !FileManager.default.fileExists(atPath: path) else {
            statusMessage = "Path already exists"
            return false
        }
        guard bufferManager.bufferIndex(forPath: path) == nil else {
            statusMessage = "Close the open buffer at that path first"
            return false
        }
        return true
    }

    private func validateMovablePath(_ sourcePath: String, destinationPath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            statusMessage = "Missing source item"
            return false
        }
        guard sourcePath != destinationPath else {
            statusMessage = "Destination must change"
            return false
        }
        guard validateCreatablePath(destinationPath) else { return false }
        guard !hasOpenBufferConflict(at: sourcePath) else {
            statusMessage = "Close open buffers before moving this item"
            return false
        }

        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let destinationURL = URL(fileURLWithPath: destinationPath).standardizedFileURL
        if destinationURL.path.hasPrefix(sourceURL.path + "/") {
            statusMessage = "Cannot move an item inside itself"
            return false
        }
        return true
    }

    private func validateDeletablePath(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            statusMessage = "Missing item"
            return false
        }
        guard SecurePath.isValid(path, root: rootPath) else {
            statusMessage = "Access denied: path outside project root"
            return false
        }
        guard !hasOpenBufferConflict(at: path) else {
            statusMessage = "Close open buffers before deleting this item"
            return false
        }
        return true
    }

    private func hasOpenBufferConflict(at path: String) -> Bool {
        bufferManager.buffers.contains { buffer in
            let bufferPath = buffer.filePath
            guard !bufferPath.isEmpty else { return false }
            return bufferPath == path || bufferPath.hasPrefix(path + "/")
        }
    }

    private func selectTreePath(_ path: String) {
        if let index = cachedFlatTree.firstIndex(where: { $0.node.path == path }) {
            selectedTreeIndex = index
            let node = cachedFlatTree[index].node
            noteSelectedPath(node.path, isDirectory: node.isDirectory)
        }
    }

    private func estimateSnapshotCost(at path: String) -> (fileCount: Int, totalBytes: Int64) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return (0, 0)
        }

        guard isDirectory.boolValue else {
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return (1, size)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        let maxFiles = config.editor.snapshotMaxFiles
        let maxBytes = Int64(config.editor.snapshotMaxBytes)

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return (0, 0)
        }

        while let relative = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(relative)
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &childIsDir) else {
                continue
            }
            guard !childIsDir.boolValue else { continue }

            fileCount += 1
            if let size = (try? fileManager.attributesOfItem(atPath: fullPath)[.size] as? Int64) {
                totalBytes += size
            }

            if fileCount > maxFiles || totalBytes > maxBytes {
                return (fileCount, totalBytes)
            }
        }

        return (fileCount, totalBytes)
    }

    private func captureFileSystemSnapshotIfReasonable(at path: String) -> FileSystemSnapshot? {
        let cost = estimateSnapshotCost(at: path)
        if cost.fileCount > config.editor.snapshotMaxFiles
            || cost.totalBytes > Int64(config.editor.snapshotMaxBytes)
        {
            return nil
        }
        return try? captureFileSystemSnapshot(at: path)
    }

    private func captureFileSystemSnapshot(at path: String) throws -> FileSystemSnapshot {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if isDirectory.boolValue {
            let children = try fileManager.contentsOfDirectory(atPath: path).sorted().map { child in
                try captureFileSystemSnapshot(at: (path as NSString).appendingPathComponent(child))
            }
            return .directory(path: path, children: children)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return .file(path: path, data: data)
    }

    private func restore(snapshot: FileSystemSnapshot) throws {
        switch snapshot {
        case .file(let path, let data):
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url)
        case .directory(let path, let children):
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true,
                attributes: nil
            )
            for child in children {
                try restore(snapshot: child)
            }
        }
    }

    private func removeItemIfExists(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }
}
