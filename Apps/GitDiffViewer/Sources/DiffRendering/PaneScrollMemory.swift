/// Where a file pane was scrolled to: the row at its top, how far into that row, and how far sideways. Kept by row
/// rather than by point, so a pane whose text is rendered anew comes back to the same line.
package struct PaneScrollPosition: Equatable, Sendable {
    /// The row whose line shows at the top of the pane.
    package let row: Int
    /// Points from the top of that row's line to the top of the pane; negative above the first row.
    package let offset: Double
    /// The horizontal scroll offset, in points.
    package let x: Double

    package init(row: Int, offset: Double, x: Double) {
        self.row = row
        self.offset = offset
        self.x = x
    }
}

/// Where the panes of each open file tab were scrolled when they last left the screen, so a tab shown again comes back
/// where it was rather than at its first change (book TAB-10). Only the files of open tabs are remembered: the owner
/// names them with ``retain(paths:)``, which forgets the others, and a record for any other file is dropped.
@MainActor
package final class PaneScrollMemory {
    /// Which pane of a file: the inline one, or one side of a split.
    package enum Pane: Hashable, Sendable {
        case unified, old, new
    }

    /// A file, by its left-side path, and one of its panes.
    package struct Key: Hashable, Sendable {
        package let path: String
        package let pane: Pane

        package init(path: String, pane: Pane) {
            self.path = path
            self.pane = pane
        }
    }

    private var positions: [Key: PaneScrollPosition] = [:]
    private var retained: Set<String> = []

    package init() {}

    /// Remembers only the files at `paths` from now on, and forgets every other.
    package func retain(paths: Set<String>) {
        retained = paths
        positions = positions.filter { paths.contains($0.key.path) }
    }

    /// Remembers `position` for `key`, unless its file is not one of the retained paths.
    package func record(_ position: PaneScrollPosition, for key: Key) {
        guard retained.contains(key.path) else { return }
        positions[key] = position
    }

    package func position(for key: Key) -> PaneScrollPosition? {
        positions[key]
    }

    /// Whether any of `panes` of the file at `path` has a position to come back to.
    package func remembers(_ path: String, panes: [Pane]) -> Bool {
        panes.contains { positions[Key(path: path, pane: $0)] != nil }
    }
}
