import Foundation

/// A node of a tree built from relative paths, identified by its path relative to the root: the explorer tree of a
/// comparison, a search result grouping, or any listing that comes as paths rather than a directory scan.
public struct PathNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public let children: [PathNode]?

    public init(id: String, name: String, isDirectory: Bool, children: [PathNode]?) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }

    /// The most components a path is shown with; a deeper one, which only a crafted patch names, becomes one leaf named
    /// by the whole path. Every walk over a tree recurses once per level, and this keeps them within a worker's stack.
    public static let maximumDepth = 256

    /// Builds a tree from relative paths. Directories sort before files, both case-insensitively. A path that is a file
    /// in one listing and a directory in another, as two sides of a comparison can be, shows as both, the directory's
    /// id taking a trailing slash so the two stay apart.
    /// - Complexity: O(paths * depth)
    public static func tree(from paths: [String]) -> [PathNode] {
        final class Builder {
            var children: [String: Builder] = [:]
            var isFile = false
        }

        let root = Builder()
        for path in paths {
            var components = path.split(separator: "/")
            if components.count > maximumDepth { components = [Substring(path)] }
            var node = root
            for component in components {
                let key = String(component)
                if let child = node.children[key] {
                    node = child
                } else {
                    let child = Builder()
                    node.children[key] = child
                    node = child
                }
            }
            node.isFile = true
        }

        // Recurses once per level, which `maximumDepth` bounds.
        func nodes(of builder: Builder, prefix: String) -> [PathNode] {
            builder.children
                .flatMap { name, child in
                    let id = prefix.isEmpty ? name : "\(prefix)/\(name)"
                    var made: [PathNode] = []
                    if child.isFile {
                        made.append(PathNode(id: id, name: name, isDirectory: false, children: nil))
                    }
                    if !child.children.isEmpty {
                        made.append(
                            PathNode(
                                id: child.isFile ? id + "/" : id, name: name, isDirectory: true,
                                children: nodes(of: child, prefix: id)))
                    }
                    return made
                }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        }

        return nodes(of: root, prefix: "")
    }

    /// One node per file, named by the file name alone, with no directories at all.
    public static func flatList(from paths: [String]) -> [PathNode] {
        paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { PathNode(id: $0, name: ($0 as NSString).lastPathComponent, isDirectory: false, children: nil) }
    }

    /// Paths of every file under this node, in tree order; the tree depth bounds the recursion.
    public var filePaths: [String] {
        guard let children else { return [id] }
        return children.flatMap(\.filePaths)
    }

    /// The id of the deepest directory reached by following single-child directory links from this node; a file
    /// or a directory that is not such a link keeps its own id. `a`, `a/b` and `a/b/c` share it in the full hierarchy,
    /// and the compacted tree names its folded row by it, so a fold survives a switch between the two styles.
    /// - Complexity: O(chain length)
    public var chainKey: String {
        var node = self
        while let children = node.children, children.count == 1, let only = children.first, only.isDirectory {
            node = only
        }
        return node.id
    }

    /// Keeps the nodes whose path satisfies `isIncluded`, and the directories leading to them.
    public func filtered(_ isIncluded: (String) -> Bool) -> PathNode? {
        guard let children else {
            return isIncluded(id) ? self : nil
        }
        let kept = children.compactMap { $0.filtered(isIncluded) }
        return kept.isEmpty ? nil : PathNode(id: id, name: name, isDirectory: true, children: kept)
    }
}

extension [PathNode] {
    /// Folds every chain of single-child directories into one node whose name is the joined path, the way
    /// compact folders work in code editors. Directories holding a single file keep their own node.
    /// - Complexity: O(nodes)
    public func compacted() -> [PathNode] {
        map { node in
            guard node.isDirectory, var children = node.children else { return node }
            var name = node.name
            var id = node.id
            while children.count == 1, let only = children.first, only.isDirectory, let grandchildren = only.children {
                name += "/" + only.name
                id = only.id
                children = grandchildren
            }
            return PathNode(id: id, name: name, isDirectory: true, children: children.compacted())
        }
    }
}
