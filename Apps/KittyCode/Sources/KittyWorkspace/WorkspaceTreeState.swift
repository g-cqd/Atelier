import Foundation
public import KittyFileTree
import System

@MainActor
public final class WorkspaceTreeState {
    public var treeNodes: [FileNode] = []
    public var cachedFlatTree: [(depth: Int, node: FileNode)] = []
    public var selectedTreeIndex: Int = 0
    public var treeScrollOffset: Int = 0
    public var lastSelectedDirectoryPath: String?

    public init() {}

    /// An empty tree for `rootPath`: `EditorState.loadInitialTree()` scans the root on the editor's pool, so building
    /// a state on the main actor never holds it for disk reads.
    public init(rootPath: String) {
        self.lastSelectedDirectoryPath = rootPath
    }

    public func noteSelectedPath(_ path: String, isDirectory: Bool) {
        let directoryPath: String
        if isDirectory {
            directoryPath = path
        } else {
            directoryPath = FilePath(path).removingLastComponent().string
        }
        lastSelectedDirectoryPath = directoryPath
    }

    public func refreshFlatTree() {
        cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        let maxIndex = max(0, cachedFlatTree.count - 1)
        treeScrollOffset = min(treeScrollOffset, maxIndex)
        selectedTreeIndex = min(selectedTreeIndex, maxIndex)
    }
}
