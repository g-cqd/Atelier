package import DiffCore
import DiffGit
import DiffRendering
package import Foundation
import Observation

/// How the two sides of a diff are laid out.
package enum ViewMode: String, CaseIterable, Identifiable {
    case inline
    /// Old on the left, new on the right.
    case split
    /// Old above, new below.
    case stacked

    package var id: String { rawValue }
}

/// Where the file explorers live relative to the diff.
package enum ExplorerPlacement: String, CaseIterable, Identifiable {
    /// One explorer per side above the diff.
    case top
    /// Both explorers stacked in a sidebar on the left.
    case sidebar
    /// A single tree on the left merging both sides.
    case unifiedSidebar

    package var id: String { rawValue }
}

/// How the explorers arrange files.
package enum FileTreeStyle: String, CaseIterable, Identifiable {
    case hierarchy
    /// Chains of single-child folders folded into one row.
    case compact
    /// Every file on its own row, named by its full path.
    case flat

    package var id: String { rawValue }
}

/// Whether the sidebar column is shown, as the user last left it. Shown by default: automatic lets the window
/// decide, and a window restored at launch sometimes decides on collapsed.
package enum SidebarVisibility: String, CaseIterable, Identifiable {
    case automatic
    case all
    case detailOnly

    package var id: String { rawValue }
}

/// User preferences, persisted in user defaults and shared by the main window, the options bar and the Settings window.
@Observable
@MainActor
package final class ViewerSettings {
    /// What a change affects, so the model knows how much to recompute.
    package enum Change {
        /// Explorer trees only.
        case trees
        /// The diff itself: files must be diffed again.
        case diff
        /// The rendered layout: prepared diffs are laid out again.
        case layout
        /// Colors and font.
        case palette
        /// Panes and chrome react by themselves.
        case appearance
    }

    /// Called after every change with what it affects, one handler per observer. Held weakly by the observer,
    /// so a closed window's model drops out on its own.
    @ObservationIgnored private var observers: [(owner: WeakOwner, handler: (Change) -> Void)] = []

    package func addObserver(_ owner: AnyObject, _ handler: @escaping (Change) -> Void) {
        observers.append((WeakOwner(owner), handler))
    }

    private final class WeakOwner {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    package var mode: ViewMode {
        didSet { store(mode.rawValue, Key.mode, (oldValue == .inline) != (mode == .inline) ? .layout : .appearance) }
    }
    package var explorerPlacement: ExplorerPlacement {
        didSet { store(explorerPlacement.rawValue, Key.explorerPlacement, .appearance) }
    }
    package var sidebarVisibility: SidebarVisibility {
        didSet { store(sidebarVisibility.rawValue, Key.sidebarVisibility, .appearance) }
    }
    package var wrapsLines: Bool { didSet { store(wrapsLines, Key.wrapsLines, .appearance) } }
    /// Keep the two panes of a split layout at the same vertical position.
    package var syncsScrolling: Bool { didSet { store(syncsScrolling, Key.syncsScrolling, .appearance) } }
    package var showsChangesOnly: Bool { didSet { store(showsChangesOnly, Key.showsChangesOnly, .trees) } }
    /// Lists the files git ignores in a section of their own, so their content can be looked at on demand.
    package var showsIgnoredFiles: Bool { didSet { store(showsIgnoredFiles, Key.showsIgnoredFiles, .trees) } }
    package var granularity: IntralineGranularity { didSet { store(granularity.rawValue, Key.granularity, .diff) } }
    /// Which diff heuristics are wired in; any change re-diffs the selection.
    package var diffHeuristics: DiffHeuristics {
        didSet { store(try? JSONEncoder().encode(diffHeuristics), Key.diffHeuristics, .diff) }
    }
    package var showsMinimap: Bool { didSet { store(showsMinimap, Key.showsMinimap, .appearance) } }
    package var showsStatusBar: Bool { didSet { store(showsStatusBar, Key.showsStatusBar, .appearance) } }
    package var treeStyle: FileTreeStyle { didSet { store(treeStyle.rawValue, Key.treeStyle, .trees) } }
    /// Characters per line when wrapping; zero wraps at the viewport width.
    package var wrapColumn: Int { didSet { store(wrapColumn, Key.wrapColumn, .appearance) } }
    /// Path of the Xcode theme file to derive colors and font from; nil keeps the system look.
    package var themePath: String? { didSet { store(themePath, Key.themePath, .palette) } }
    /// Show only the changed regions with context, in every layout.
    package var isolatesChanges: Bool { didSet { store(isolatesChanges, Key.isolatesChanges, .layout) } }
    /// Unchanged rows kept around each change when changes are isolated.
    package var contextLines: Int { didSet { store(contextLines, Key.contextLines, .layout) } }
    /// Line height as a multiple of the font's; zero follows the theme (1.0 for the system palette).
    package var lineHeightMultiple: Double { didSet { store(lineHeightMultiple, Key.lineHeightMultiple, .layout) } }

    private let defaults: UserDefaults

    private func store(_ value: Any?, _ key: String, _ change: Change) {
        defaults.set(value, forKey: key)
        observers.removeAll { $0.owner.object == nil }
        for observer in observers { observer.handler(change) }
    }

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Key.mode).flatMap(ViewMode.init(rawValue:)) ?? .split
        explorerPlacement =
            defaults.string(forKey: Key.explorerPlacement).flatMap(ExplorerPlacement.init(rawValue:)) ?? .top
        sidebarVisibility =
            defaults.string(forKey: Key.sidebarVisibility).flatMap(SidebarVisibility.init(rawValue:)) ?? .all
        wrapsLines = defaults.object(forKey: Key.wrapsLines) as? Bool ?? true
        syncsScrolling = defaults.object(forKey: Key.syncsScrolling) as? Bool ?? true
        showsChangesOnly = defaults.bool(forKey: Key.showsChangesOnly)
        showsIgnoredFiles = defaults.bool(forKey: Key.showsIgnoredFiles)
        granularity = defaults.string(forKey: Key.granularity).flatMap(IntralineGranularity.init(rawValue:)) ?? .word
        diffHeuristics =
            defaults.data(forKey: Key.diffHeuristics)
            .flatMap { try? JSONDecoder().decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
        showsMinimap = defaults.object(forKey: Key.showsMinimap) as? Bool ?? true
        showsStatusBar = defaults.object(forKey: Key.showsStatusBar) as? Bool ?? true
        treeStyle =
            defaults.string(forKey: Key.treeStyle).flatMap(FileTreeStyle.init(rawValue:))
            ?? (defaults.bool(forKey: Key.compactsFolders) ? .compact : .hierarchy)
        wrapColumn = defaults.integer(forKey: Key.wrapColumn)
        themePath = defaults.string(forKey: Key.themePath)
        lineHeightMultiple = defaults.double(forKey: Key.lineHeightMultiple)
        contextLines = defaults.object(forKey: Key.contextLines) as? Int ?? 3
        isolatesChanges = defaults.bool(forKey: Key.isolatesChanges)
    }

    private enum Key {
        static let mode = "viewMode"
        static let explorerPlacement = "explorerPlacement"
        static let sidebarVisibility = "sidebarVisibility"
        static let wrapsLines = "wrapsLines"
        static let syncsScrolling = "syncsScrolling"
        static let showsChangesOnly = "showsChangesOnly"
        static let showsIgnoredFiles = "showsIgnoredFiles"
        static let granularity = "intralineGranularity"
        static let diffHeuristics = "diffHeuristics"
        static let showsMinimap = "showsMinimap"
        static let showsStatusBar = "showsStatusBar"
        static let compactsFolders = "compactsFolders"
        static let treeStyle = "fileTreeStyle"
        static let wrapColumn = "wrapColumn"
        static let themePath = "themePath"
        static let lineHeightMultiple = "lineHeightMultiple"
        static let contextLines = "contextLines"
        static let isolatesChanges = "isolatesChanges"
    }
}
