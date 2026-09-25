import AtelierFileTree
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// What one explorer remembers between rebuilds of its tree: the folders and sections the user folded or unfolded.
/// Owned by the window, so it outlives a change of placement, and keyed by ``PathNode/chainKey``, or by a section's
/// id, so it survives a change of tree style and a reload (GIT-06 criterion 3). Folders start expanded, so the
/// auto-selected file is visible; a section may start folded instead (``ExplorerSection/collapsedByDefault(_:)``).
@MainActor
package final class ExplorerUIState {
    package private(set) var collapsed: Set<String> = []
    /// Rows the user unfolded against a default of folded, so the default does not fold them again.
    package private(set) var expanded: Set<String> = []

    package init() {}

    /// Whether the row under `key` is folded: as the user left it, else `byDefault`.
    package func isCollapsed(_ key: String, byDefault: Bool = false) -> Bool {
        if collapsed.contains(key) { return true }
        if expanded.contains(key) { return false }
        return byDefault
    }

    package func setCollapsed(_ isCollapsed: Bool, _ key: String) {
        if isCollapsed {
            collapsed.insert(key)
            expanded.remove(key)
        } else {
            collapsed.remove(key)
            expanded.insert(key)
        }
    }
}
