package import AtelierDiagnostics
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

/// Which side of a comparison diagnostics tools analyze. Findings come from the tools running against the newer
/// (on-disk) side, so the old side's rows only ever get a best-effort echo of a finding that also names the same
/// line number on the old side — never an independent analysis of the old content itself.
package enum AnalyzedSides: String, CaseIterable, Identifiable, Codable {
    /// Only the newer side is analyzed; the older side never shows diagnostics.
    case newer
    /// The newer side is analyzed as usual, and its findings are echoed onto old-side rows that share the same
    /// line number — useful context on a removed or changed line, not a genuine analysis of the old content.
    case both

    package var id: String { rawValue }
}

/// The Settings window's tabs, persisted so the window reopens on whichever the user last looked at.
package enum SettingsPane: String, CaseIterable, Identifiable, Codable {
    case general
    case diff
    case appearance
    case tools

    package var id: String { rawValue }
}

/// A group of related settings a Settings tab shows together, for per-tab "Restore Defaults".
package enum SettingsCategory: CaseIterable {
    case general
    case diff
    case appearance
    case tools
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
        /// Diagnostics must be re-run, or cleared when the master toggle turns off.
        case diagnostics
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
    /// Master toggle for the diagnostics track; off cancels any run in flight and clears findings.
    package var diagnosticsEnabled: Bool {
        didSet { store(diagnosticsEnabled, Key.diagnosticsEnabled, .diagnostics) }
    }
    /// Shown as its own setting rather than folded into `.diagnostics`: it toggles a hover popover the same way
    /// every other appearance flag toggles a piece of chrome, with nothing to re-run or recompute.
    package var showsHoverDocumentation: Bool {
        didSet { store(showsHoverDocumentation, Key.showsHoverDocumentation, .appearance) }
    }
    /// Per-tool enablement and custom executable path, keyed by tool; every tool is enabled by default.
    package var toolLocations: [DiagnosticTool: ToolLocation] {
        didSet {
            let encoded = Dictionary(uniqueKeysWithValues: toolLocations.map { ($0.key.rawValue, $0.value) })
            store(try? JSONEncoder().encode(encoded), Key.toolLocations, .diagnostics)
        }
    }
    /// Per-server overrides for tools discovered the same way but not in ``DiagnosticTool``, such as
    /// `sourcekit-lsp`; keyed by a server id rather than a typed enum since the set is open-ended.
    package var lspServerLocations: [String: ToolLocation] {
        didSet { store(try? JSONEncoder().encode(lspServerLocations), Key.lspServerLocations, .diagnostics) }
    }
    /// Which side(s) of a comparison diagnostics findings are mapped onto.
    package var analyzedSides: AnalyzedSides {
        didSet { store(analyzedSides.rawValue, Key.analyzedSides, .diagnostics) }
    }
    /// The Settings window's last-viewed tab, restored the next time it opens.
    package var settingsPane: SettingsPane {
        didSet { store(settingsPane.rawValue, Key.settingsPane, .appearance) }
    }

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
        diagnosticsEnabled = defaults.bool(forKey: Key.diagnosticsEnabled)
        showsHoverDocumentation = defaults.object(forKey: Key.showsHoverDocumentation) as? Bool ?? true
        toolLocations =
            defaults.data(forKey: Key.toolLocations)
            .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) }
            .map { decoded in
                Dictionary(
                    uniqueKeysWithValues: decoded.compactMap { key, value in
                        DiagnosticTool(rawValue: key).map { ($0, value) }
                    })
            }
            ?? Dictionary(uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
        lspServerLocations =
            defaults.data(forKey: Key.lspServerLocations)
            .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) }
            ?? ["sourcekit-lsp": ToolLocation()]
        analyzedSides =
            defaults.string(forKey: Key.analyzedSides).flatMap(AnalyzedSides.init(rawValue:)) ?? .newer
        settingsPane =
            defaults.string(forKey: Key.settingsPane).flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    /// Resets every setting in `category` to its coded default, going through the same setters as a user edit so
    /// each one stores to user defaults and fires its observers exactly as it would for a manual change.
    package func restoreDefaults(_ category: SettingsCategory) {
        switch category {
            case .general:
                explorerPlacement = .top
                treeStyle = .hierarchy
                showsChangesOnly = false
                showsIgnoredFiles = false
                syncsScrolling = true
                showsMinimap = true
                showsStatusBar = true
            case .diff:
                isolatesChanges = false
                contextLines = 3
                granularity = .word
                diffHeuristics = DiffHeuristics()
            case .appearance:
                themePath = nil
                lineHeightMultiple = 0
                mode = .split
                wrapsLines = true
                wrapColumn = 0
            case .tools:
                diagnosticsEnabled = false
                showsHoverDocumentation = true
                analyzedSides = .newer
                toolLocations = Dictionary(uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
                lspServerLocations = ["sourcekit-lsp": ToolLocation()]
        }
    }

    /// How many settings in `category` currently differ from their coded default, for the tab footer's subtle
    /// deviation indicator (P6): cheap enough to recompute on every render since each category is a handful of
    /// comparisons.
    package func settingsDiffCount(_ category: SettingsCategory) -> Int {
        switch category {
            case .general:
                return [
                    explorerPlacement != .top, treeStyle != .hierarchy, showsChangesOnly != false,
                    showsIgnoredFiles != false, syncsScrolling != true, showsMinimap != true,
                    showsStatusBar != true
                ]
                .count { $0 }
            case .diff:
                return [
                    isolatesChanges != false, contextLines != 3, granularity != .word,
                    diffHeuristics != DiffHeuristics()
                ]
                .count { $0 }
            case .appearance:
                return [
                    themePath != nil, lineHeightMultiple != 0, mode != .split, wrapsLines != true, wrapColumn != 0
                ]
                .count { $0 }
            case .tools:
                let defaultToolLocations = Dictionary(
                    uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
                return [
                    diagnosticsEnabled != false, showsHoverDocumentation != true, analyzedSides != .newer,
                    toolLocations != defaultToolLocations, lspServerLocations != ["sourcekit-lsp": ToolLocation()]
                ]
                .count { $0 }
        }
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
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let showsHoverDocumentation = "hoverDocumentation"
        static let toolLocations = "diagnosticToolLocations"
        static let lspServerLocations = "lspServerLocations"
        static let analyzedSides = "analyzedSides"
        static let settingsPane = "settingsPane"
    }
}
