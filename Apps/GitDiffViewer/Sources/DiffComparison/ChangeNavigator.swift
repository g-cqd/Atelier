import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// Position among the changes of a file, or among the cards of a list.
package struct ChangeNavigator: Equatable {
    package private(set) var index = -1

    /// One-based position for display, when a change is current.
    package func current(count: Int) -> Int? {
        index >= 0 && index < count ? index + 1 : nil
    }

    package mutating func reset() {
        index = -1
    }

    package mutating func focusFirst() {
        index = 0
    }

    package mutating func next(count: Int) {
        guard count > 0 else { return }
        index = (index + 1) % count
    }

    package mutating func previous(count: Int) {
        guard count > 0 else { return }
        index = index <= 0 ? count - 1 : index - 1
    }
}
