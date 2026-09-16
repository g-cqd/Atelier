import DiffConcurrency
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// One group of an explorer: the compared files, or the files git ignores when they are shown as well. With one
/// section the explorer shows its rows plainly; with two, each becomes a collapsible group.
package struct ExplorerSection: Equatable, Sendable, Identifiable {
    package enum Kind: String, Sendable {
        case changes
        case ignored
    }

    package let kind: Kind
    package let title: String
    package let nodes: [FileNode]

    package init(kind: Kind, title: String, nodes: [FileNode]) {
        self.kind = kind
        self.title = title
        self.nodes = nodes
    }

    package var id: String { kind.rawValue }
}
