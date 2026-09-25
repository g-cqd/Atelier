package import AtelierFileTree
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// One group of an explorer: the compared files, the files git ignores when they are shown as well, or, when the
/// merged sidebar's flat list is grouped by commit, one commit's files (GIT-06). With one section the explorer shows
/// its rows plainly; with several, each becomes a collapsible group.
package struct ExplorerSection: Equatable, Sendable, Identifiable {
    package enum Kind: Equatable, Sendable {
        case changes
        case ignored
        /// A section of the grouped list: Uncommitted Changes, a commit, or Earlier Changes.
        case commitGroup(CommitGrouping.Section)
    }

    package let kind: Kind
    package let title: String
    package let nodes: [PathNode]

    package init(kind: Kind, title: String, nodes: [PathNode]) {
        self.kind = kind
        self.title = title
        self.nodes = nodes
    }

    /// Stable across rebuilds; a commit group's is its ``CommitGrouping/Section/id``, which its fold is kept under.
    package var id: String {
        switch kind {
            case .changes: "changes"
            case .ignored: "ignored"
            case .commitGroup(let group): group.id
        }
    }

    /// The commit group this section shows; nil for the plain and ignored sections.
    package var commitGroup: CommitGrouping.Section? {
        if case .commitGroup(let group) = kind { group } else { nil }
    }

    /// A section of the grouped list, titled by its commit's subject, or by its fixed name.
    package init(group: CommitGrouping.Section) {
        let title =
            switch group.kind {
                case .uncommitted: "Uncommitted Changes"
                case .commit(let commit): commit.subject.isEmpty ? GitCommit.abbreviated(commit.id) : commit.subject
                case .earlier: "Earlier Changes"
            }
        // The rows come in the flat list's order already; sorting them again would cost as much as the grouping.
        let nodes = group.rows.map {
            PathNode(id: $0.path, name: ($0.path as NSString).lastPathComponent, isDirectory: false, children: nil)
        }
        self.init(kind: .commitGroup(group), title: title, nodes: nodes)
    }
}
