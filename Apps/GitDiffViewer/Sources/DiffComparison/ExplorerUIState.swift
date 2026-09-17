import AtelierFileTree
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// What one explorer remembers between rebuilds of its tree: the folders the user folded. Owned by the window, so
/// it outlives a change of placement, and keyed by ``PathNode/chainKey`` so it survives a change of tree style.
/// Everything starts expanded, so the auto-selected file is visible.
@MainActor
package final class ExplorerUIState {
    package private(set) var collapsed: Set<String> = []

    package init() {}

    package func isCollapsed(_ chainKey: String) -> Bool {
        collapsed.contains(chainKey)
    }

    package func setCollapsed(_ isCollapsed: Bool, _ chainKey: String) {
        if isCollapsed { collapsed.insert(chainKey) } else { collapsed.remove(chainKey) }
    }
}
