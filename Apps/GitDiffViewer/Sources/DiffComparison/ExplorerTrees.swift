package import AtelierFileTree
import DiffCore
package import DiffGit
import DiffRendering
import Foundation
import Observation

/// The explorer trees for both sides and the merged view, with every directory carrying the aggregate status of
/// its files. Built as one value from the comparison and the display settings.
package struct ExplorerTrees: Sendable, Equatable {
    package var left: [PathNode] = []
    package var right: [PathNode] = []
    /// Both sides merged into one tree, keyed by left-side paths.
    package var unified: [PathNode] = []
    /// The files git ignores on each side, and both together, when they are shown; empty otherwise.
    package var leftIgnored: [PathNode] = []
    package var rightIgnored: [PathNode] = []
    package var unifiedIgnored: [PathNode] = []
    /// Status of every file and directory by left-side path; a directory takes the aggregate of its files.
    package var statuses: [String: PathStatus] = [:]

    package static let empty = ExplorerTrees()

    package static func build(
        comparison: Comparison, leftTree: [PathNode], rightTree: [PathNode], showsChangesOnly: Bool,
        showsIgnoredFiles: Bool = false, style: FileTreeStyle
    ) -> ExplorerTrees {
        var trees = ExplorerTrees()
        var leftNodes = leftTree
        var rightNodes = rightTree
        // The statuses hold every compared path once, keyed by the left side; the entries would add the ignored files.
        var unifiedNodes = PathNode.tree(from: Array(comparison.statuses.keys))
        trees.statuses = comparison.statuses
        for node in leftNodes + rightNodes + unifiedNodes {
            trees.aggregateStatus(of: node)
        }
        if showsChangesOnly {
            let statuses = comparison.statuses
            leftNodes = leftNodes.compactMap { $0.filtered { statuses[$0] != .same } }
            rightNodes = rightNodes.compactMap {
                $0.filtered { statuses[comparison.counterpartPath(of: $0, in: .right)] != .same }
            }
            unifiedNodes = unifiedNodes.compactMap { $0.filtered { statuses[$0] != .same } }
        }
        trees.left = arranged(leftNodes, style: style)
        trees.right = arranged(rightNodes, style: style)
        trees.unified = arranged(unifiedNodes, style: style)
        if showsIgnoredFiles {
            let leftIgnored = comparison.ignoredPaths.filter { comparison.leftEntries[$0] != nil }
            let rightIgnored = comparison.ignoredPaths.filter { comparison.rightEntries[$0] != nil }
            trees.leftIgnored = arranged(PathNode.tree(from: Array(leftIgnored)), style: style)
            trees.rightIgnored = arranged(PathNode.tree(from: Array(rightIgnored)), style: style)
            trees.unifiedIgnored = arranged(PathNode.tree(from: Array(comparison.ignoredPaths)), style: style)
        }
        return trees
    }

    private static func arranged(_ nodes: [PathNode], style: FileTreeStyle) -> [PathNode] {
        switch style {
            case .hierarchy: nodes
            case .compact: nodes.compacted()
            case .flat: PathNode.flatList(from: nodes.flatMap(\.filePaths))
        }
    }

    /// A directory is same when all its files are, one-sided when all its files are, and different otherwise.
    /// The tree depth bounds the recursion.
    @discardableResult
    private mutating func aggregateStatus(of node: PathNode) -> PathStatus? {
        guard let children = node.children else { return statuses[node.id] }
        var aggregate: PathStatus?
        for child in children {
            guard let status = aggregateStatus(of: child) else { continue }
            aggregate =
                switch aggregate {
                    case nil, status: status
                    default: .different
                }
        }
        statuses[node.id] = aggregate
        return aggregate
    }
}
