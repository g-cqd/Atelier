import DiffCore
import DiffGit
package import DiffRendering
import Foundation
import Observation

/// What a file badge shows: the kind of change and its line counts.
package struct FileChangeSummary: Equatable {
    package enum Kind: Equatable {
        case added
        case deleted
        case modified
        case renamed(to: String)
    }

    package let kind: Kind
    package let addedLines: Int
    package let removedLines: Int
}

/// Lines added and removed, and how many files changed. The line counts cover every changed file when the file
/// list is on screen; with one file selected they are that file's, and `coversEveryFile` says so.
package struct DiffTotals: Equatable {
    package let files: Int
    package let added: Int
    package let removed: Int
    package let coversEveryFile: Bool

    package init(files: Int, added: Int, removed: Int, coversEveryFile: Bool) {
        self.files = files
        self.added = added
        self.removed = removed
        self.coversEveryFile = coversEveryFile
    }
}

/// What the detail area shows.
package enum DetailState: Equatable {
    case noSources
    case loading
    case error(String)
    case noSelection
    case noChanges
    case file(RenderedDiff)
    case cards

    package static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
            case (.noSources, .noSources), (.loading, .loading), (.noSelection, .noSelection), (.noChanges, .noChanges),
                (.cards, .cards):
                true
            case (.error(let a), .error(let b)): a == b
            case (.file(let a), .file(let b)): a.unified?.id == b.unified?.id && a.old?.id == b.old?.id
            default: false
        }
    }
}

/// How what the detail area shows relates to what the window asks for, so a previous comparison kept on screen never
/// reads as current (book D13).
package enum ShownComparison: Equatable {
    /// What is shown is what the window asks for, or nothing is shown.
    case current
    /// What is shown is the previous comparison, or the previous selection, kept while the one asked for loads.
    case previous
    /// What is shown is the previous comparison, kept because the one asked for failed to load or render.
    case previousAfterFailure(String)
}

/// How long the current operation took, counted from the change that started it: a selection, a diff option, or
/// a source.
package struct RenderTiming: Equatable, Sendable {
    /// Until the first pane put its text on screen: the file, or the first card of a list.
    package var firstDisplay: Duration?
    /// Until every file of the operation was rendered.
    package var rendered: Duration?
}

package struct RenderedFile: Identifiable, Sendable {
    package let path: String
    package let rendered: RenderedDiff

    package var id: String { path }
}

package enum Side: Sendable {
    case left
    case right
}
