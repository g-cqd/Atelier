import Foundation
import KittyFileTree

extension EditorState {
    @discardableResult
    func createTreeFile(at destinationPath: String, suggestedDirectory _: String) async -> Bool {
        guard validateCreatablePath(destinationPath) else { return false }

        let destinationURL = URL(fileURLWithPath: destinationPath)
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
            fileTreeHistory.record(.create(snapshot: .file(path: destinationPath, data: Data())), currentNodes: treeNodes)
            statusMessage = "Created \(destinationURL.lastPathComponent)"
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error creating file: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func createTreeDirectory(at destinationPath: String, suggestedDirectory _: String) async -> Bool {
        guard validateCreatablePath(destinationPath) else { return false }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: destinationPath),
                withIntermediateDirectories: true,
                attributes: nil
            )

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            fileTreeHistory.record(.create(snapshot: .directory(path: destinationPath, children: [])), currentNodes: treeNodes)
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
        guard validateMovablePath(sourcePath, destinationPath: destinationPath) else { return false }

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
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
            let snapshot = try captureFileSystemSnapshot(at: destinationPath)

            await loadInitialTree(validateHistory: false)
            selectTreePath(destinationPath)
            fileTreeHistory.record(.duplicate(snapshot: snapshot), currentNodes: treeNodes)
            statusMessage = "Duplicated \(destinationURL.lastPathComponent)"
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

        do {
            let snapshot = try captureFileSystemSnapshot(at: path)
            try FileManager.default.removeItem(atPath: path)

            await loadInitialTree(validateHistory: false)
            selectTreePath(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            fileTreeHistory.record(.delete(snapshot: snapshot), currentNodes: treeNodes)
            statusMessage = "Deleted \(URL(fileURLWithPath: path).lastPathComponent)"
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error deleting item: \(error.localizedDescription)"
            return false
        }
    }

    func undoFileTreeOperation() async {
        switch fileTreeHistory.undo(currentNodes: treeNodes) {
        case .applied(let operation):
            let success = await applyUndo(operation)
            if success {
                statusMessage = "Undo file operation"
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
        case .applied(let operation):
            let success = await applyRedo(operation)
            if success {
                statusMessage = "Redo file operation"
            } else {
                fileTreeHistory.clear(currentNodes: treeNodes)
            }
        case .unavailable:
            statusMessage = "Nothing to redo"
        case .invalidated:
            statusMessage = "File history cleared after tree refresh"
        }
    }

    private func applyUndo(_ operation: FileTreeOperation) async -> Bool {
        do {
            switch operation {
            case .create(let snapshot):
                try removeItemIfExists(at: snapshot.path)
                await loadInitialTree(validateHistory: false)
                selectTreePath(URL(fileURLWithPath: snapshot.path).deletingLastPathComponent().path)
            case .delete(let snapshot):
                try restore(snapshot: snapshot)
                await loadInitialTree(validateHistory: false)
                selectTreePath(snapshot.path)
            case .move(let sourcePath, let destinationPath):
                try FileManager.default.moveItem(atPath: destinationPath, toPath: sourcePath)
                await loadInitialTree(validateHistory: false)
                selectTreePath(sourcePath)
            case .duplicate(let snapshot):
                try removeItemIfExists(at: snapshot.path)
                await loadInitialTree(validateHistory: false)
                selectTreePath(URL(fileURLWithPath: snapshot.path).deletingLastPathComponent().path)
            }

            fileTreeHistory.updateCurrent(nodes: treeNodes)
            renderRefreshSource?.invalidate()
            return true
        } catch {
            statusMessage = "Error undoing file operation: \(error.localizedDescription)"
            return false
        }
    }

    private func applyRedo(_ operation: FileTreeOperation) async -> Bool {
        do {
            switch operation {
            case .create(let snapshot), .duplicate(let snapshot):
                try restore(snapshot: snapshot)
                await loadInitialTree(validateHistory: false)
                selectTreePath(snapshot.path)
            case .delete(let snapshot):
                try removeItemIfExists(at: snapshot.path)
                await loadInitialTree(validateHistory: false)
                selectTreePath(URL(fileURLWithPath: snapshot.path).deletingLastPathComponent().path)
            case .move(let sourcePath, let destinationPath):
                try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
                await loadInitialTree(validateHistory: false)
                selectTreePath(destinationPath)
            }

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
