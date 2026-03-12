import Foundation

/// Tree operations for flattening and mutating a ``FileNode`` hierarchy.
public enum FileTreeNavigator {
    /// A single visible row — the node paired with its indentation depth.
    public typealias FlatEntry = (depth: Int, node: FileNode)

    /// Produces a depth-first, pre-order flat list of visible nodes.
    ///
    /// Only expanded directories contribute their children to the output,
    /// making this suitable for rendering a collapsible tree in a terminal.
    ///
    /// - Parameters:
    ///   - nodes: The top-level node array.
    ///   - depth: Starting indentation depth (defaults to `0`).
    /// - Returns: Ordered flat list of `(depth, node)` pairs.
    public static func flatten(_ nodes: [FileNode], depth: Int = 0) -> [FlatEntry] {
        var result: [FlatEntry] = []
        for node in nodes {
            result.append((depth: depth, node: node))
            if node.isDirectory && node.isExpanded {
                result.append(contentsOf: flatten(node.children, depth: depth + 1))
            }
        }
        return result
    }

    /// Toggles the expanded state of the node whose ``FileNode/path`` equals
    /// `path`, searching the tree recursively.
    ///
    /// When a directory is expanded for the first time and its `children`
    /// array is empty, ``DirectoryScanner/scan(_:maxDepth:maxEntries:)`` is
    /// called with `maxDepth: 1` to populate one level of children eagerly.
    ///
    /// - Parameters:
    ///   - nodes: The root node array, mutated in place.
    ///   - path: Absolute path identifying the node to toggle.
    public static func toggleExpand(
        in nodes: inout [FileNode], at path: String, visibility: FileVisibility = .defaultHidden
    ) {
        for i in nodes.indices {
            if nodes[i].path == path {
                nodes[i].isExpanded.toggle()
                if nodes[i].isExpanded && nodes[i].children.isEmpty {
                    nodes[i].children = DirectoryScanner.scan(
                        nodes[i].path, maxDepth: 1, visibility: visibility)
                }
                return
            }
            if nodes[i].isDirectory {
                toggleExpand(in: &nodes[i].children, at: path, visibility: visibility)
            }
        }
    }
}
