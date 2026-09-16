import DiffCore
package import DiffGit
import DiffRendering
import Foundation
import Observation
/// Which cards are folded: the user's choices, plus wholly added and deleted files folded by default when a list
/// first appears.
package struct CardFolding: Equatable {
    package private(set) var collapsed: Set<String> = []
    private var foldsNoiseByDefault = true

    package mutating func reset() {
        collapsed = []
        foldsNoiseByDefault = true
    }

    package mutating func toggle(_ path: String) {
        if collapsed.remove(path) == nil { collapsed.insert(path) }
    }

    package mutating func setAll(_ paths: [String], collapsed isCollapsed: Bool) {
        collapsed = isCollapsed ? Set(paths) : []
    }

    /// Folds the noise among newly published cards until the list is complete.
    package mutating func applyDefaults(to paths: [String], status: (String) -> PathStatus?) {
        guard foldsNoiseByDefault else { return }
        collapsed.formUnion(paths.filter { [.onlyLeft, .onlyRight].contains(status($0)) })
    }

    package mutating func listCompleted() {
        foldsNoiseByDefault = false
    }
}
