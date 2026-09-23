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

/// Which side of a comparison diagnostics are shown on. Tools only ever analyze the newer (on-disk) side.
package enum AnalyzedSides: String, CaseIterable, Identifiable, Codable {
    /// Only the newer side is analyzed; the older side never shows diagnostics.
    case newer
    /// The newer side's findings are also echoed onto old-side rows with the same line number.
    case both

    package var id: String { rawValue }
}

/// Whether the window chrome follows the system's light/dark choice or is pinned to one, independently of the theme.
package enum AppearanceScheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

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
        /// ``autoRefresh`` flipped: the window's ``RepositoryFreshness`` watcher attaches or tears down.
        case freshness
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

    /// The project whose overrides overlay the app defaults; nil until ``adoptProject(_:)``.
    package internal(set) var projectID: ProjectIdentity?

    /// Settings whose value may vary from one project to the next; everything else stays app-wide.
    static let projectScopedKeys: Set<String> = [
        Key.diagnosticsEnabled, Key.analyzedSides, Key.toolLocations, Key.lspServerLocations, Key.contextLines,
        Key.showsChangesOnly, Key.showsIgnoredFiles, Key.diffHeuristics, Key.treeStyle
    ]

    static let projectRegistryKey = "projectRegistry"

    static func scopedKey(_ key: String, projectKey: String) -> String {
        "project.\(projectKey).\(key)"
    }

    func scopedKey(_ key: String, for projectID: ProjectIdentity) -> String {
        Self.scopedKey(key, projectKey: projectID.key)
    }

    /// The key a read of `key` hits: the adopted project's scoped key once it holds an override, the base key
    /// otherwise, so a project inherits the app default until its first override.
    func effectiveKey(_ key: String) -> String {
        guard let projectID, Self.projectScopedKeys.contains(key) else { return key }
        let scoped = scopedKey(key, for: projectID)
        return defaults.object(forKey: scoped) != nil ? scoped : key
    }

    /// Records `id` in the project registry (key to display path), so Settings can list the projects with overrides
    /// without scanning every defaults key.
    func registerProject(_ id: ProjectIdentity) {
        var registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        guard registry[id.key] != id.displayPath else { return }
        registry[id.key] = id.displayPath
        defaults.set(registry, forKey: Self.projectRegistryKey)
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
    /// Whether the window watches the working tree and the repository's `.git` metadata for external changes and
    /// reloads on its own.
    package var autoRefresh: Bool { didSet { store(autoRefresh, Key.autoRefresh, .freshness) } }
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
    /// Whether hovering a symbol shows its documentation.
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
    /// Per-server overrides for language servers outside ``DiagnosticTool``, such as `sourcekit-lsp`, by server id.
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
    /// The light/dark appearance of the window chrome, the Settings window included.
    package var appearanceScheme: AppearanceScheme {
        didSet { store(appearanceScheme.rawValue, Key.appearanceScheme, .appearance) }
    }
    /// Which colours a change badge's letter is drawn in: classic red/green/orange/purple, or Xcode's own.
    package var badgeScheme: BadgeScheme { didSet { store(badgeScheme.rawValue, Key.badgeScheme, .appearance) } }
    /// Whether the window follows the selected theme's own light/dark background instead of the system's, when
    /// ``appearanceScheme`` is ``AppearanceScheme/system`` -- an explicit light/dark pin always wins.
    package var matchesThemeAppearance: Bool {
        didSet { store(matchesThemeAppearance, Key.matchesThemeAppearance, .appearance) }
    }

    let defaults: UserDefaults

    /// Set while scoped properties are reassigned their base value after their override was removed, so `store`
    /// notifies observers without writing the override back.
    @ObservationIgnored private var isFallingBackToBase = false

    func applyWithoutRecreatingScopedOverrides(_ body: () -> Void) {
        isFallingBackToBase = true
        defer { isFallingBackToBase = false }
        body()
    }

    /// Set while another instance's broadcast base-key change is applied, so `store` doesn't re-broadcast it.
    @ObservationIgnored var isApplyingBroadcast = false
    /// `nonisolated(unsafe)`: written once at the end of `init` and read once in the nonisolated `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var baseSettingObserver: (any NSObjectProtocol)?

    private func store(_ value: Any?, _ key: String, _ change: Change) {
        if let projectID, Self.projectScopedKeys.contains(key) {
            if !isFallingBackToBase {
                defaults.set(value, forKey: scopedKey(key, for: projectID))
                registerProject(projectID)
            }
        } else {
            defaults.set(value, forKey: key)
            if !isApplyingBroadcast { postBaseSettingChanged(key: key) }
        }
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
        autoRefresh = defaults.object(forKey: Key.autoRefresh) as? Bool ?? true
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
        toolLocations = Self.decodeToolLocations(defaults.data(forKey: Key.toolLocations))
        lspServerLocations =
            defaults.data(forKey: Key.lspServerLocations)
            .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) }
            ?? ["sourcekit-lsp": ToolLocation()]
        analyzedSides =
            defaults.string(forKey: Key.analyzedSides).flatMap(AnalyzedSides.init(rawValue:)) ?? .newer
        settingsPane =
            defaults.string(forKey: Key.settingsPane).flatMap(SettingsPane.init(rawValue:)) ?? .general
        appearanceScheme =
            defaults.string(forKey: Key.appearanceScheme).flatMap(AppearanceScheme.init(rawValue:)) ?? .system
        badgeScheme = defaults.string(forKey: Key.badgeScheme).flatMap(BadgeScheme.init(rawValue:)) ?? .classic
        matchesThemeAppearance = defaults.object(forKey: Key.matchesThemeAppearance) as? Bool ?? false
        baseSettingObserver = NotificationCenter.default.addObserver(
            forName: Self.baseSettingChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let poster = notification.object else { return }
            guard let key = notification.userInfo?[Self.baseSettingChangedKey] as? String else { return }
            let posterID = ObjectIdentifier(poster as AnyObject)
            MainActor.assumeIsolated { self?.baseSettingChanged(posterID: posterID, key: key) }
        }
    }

    deinit {
        if let baseSettingObserver { NotificationCenter.default.removeObserver(baseSettingObserver) }
    }

    /// Resets every setting in `category` to its coded default through the same setters as a user edit. Once a
    /// project is adopted, a scoped setting instead drops the project's override and falls back to the base value.
    package func restoreDefaults(_ category: SettingsCategory) {
        applyWithoutRecreatingScopedOverrides { restoreDefaultsUnguarded(category) }
    }

    private func restoreDefaultsUnguarded(_ category: SettingsCategory) {
        switch category {
            case .general:
                explorerPlacement = .top
                treeStyle = restoredValue(Key.treeStyle, appDefault: FileTreeStyle.hierarchy) {
                    defaults.string(forKey: Key.treeStyle).flatMap(FileTreeStyle.init(rawValue:)) ?? .hierarchy
                }
                showsChangesOnly = restoredValue(Key.showsChangesOnly, appDefault: false) {
                    defaults.bool(forKey: Key.showsChangesOnly)
                }
                showsIgnoredFiles = restoredValue(Key.showsIgnoredFiles, appDefault: false) {
                    defaults.bool(forKey: Key.showsIgnoredFiles)
                }
                syncsScrolling = true
                showsMinimap = true
                showsStatusBar = true
                autoRefresh = true
            case .diff:
                isolatesChanges = false
                contextLines = restoredValue(Key.contextLines, appDefault: 3) {
                    defaults.object(forKey: Key.contextLines) as? Int ?? 3
                }
                granularity = .word
                diffHeuristics = restoredValue(Key.diffHeuristics, appDefault: DiffHeuristics()) {
                    defaults.data(forKey: Key.diffHeuristics)
                        .flatMap { try? JSONDecoder().decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
                }
            case .appearance:
                themePath = nil
                lineHeightMultiple = 0
                mode = .split
                wrapsLines = true
                wrapColumn = 0
                appearanceScheme = .system
                badgeScheme = .classic
                matchesThemeAppearance = false
            case .tools:
                diagnosticsEnabled = restoredValue(Key.diagnosticsEnabled, appDefault: false) {
                    defaults.bool(forKey: Key.diagnosticsEnabled)
                }
                showsHoverDocumentation = true
                analyzedSides = restoredValue(Key.analyzedSides, appDefault: AnalyzedSides.newer) {
                    defaults.string(forKey: Key.analyzedSides).flatMap(AnalyzedSides.init(rawValue:)) ?? .newer
                }
                toolLocations = restoredValue(
                    Key.toolLocations,
                    appDefault: Dictionary(uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
                ) { Self.decodeToolLocations(defaults.data(forKey: Key.toolLocations)) }
                lspServerLocations = restoredValue(
                    Key.lspServerLocations, appDefault: ["sourcekit-lsp": ToolLocation()]
                ) {
                    defaults.data(forKey: Key.lspServerLocations)
                        .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) }
                        ?? ["sourcekit-lsp": ToolLocation()]
                }
        }
    }

    /// Clears `key`'s project override (if any) and returns what the property should become: the base value,
    /// decoded by `decodeBase`, when a project is adopted, or the coded app-wide default otherwise.
    private func restoredValue<Value>(_ key: String, appDefault: Value, decodeBase: () -> Value) -> Value {
        guard let projectID else { return appDefault }
        defaults.removeObject(forKey: scopedKey(key, for: projectID))
        return decodeBase()
    }

    static func decodeToolLocations(_ data: Data?) -> [DiagnosticTool: ToolLocation] {
        data
            .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) }
            .map { decoded in
                Dictionary(
                    uniqueKeysWithValues: decoded.compactMap { key, value in
                        DiagnosticTool(rawValue: key).map { ($0, value) }
                    })
            }
            ?? Dictionary(uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
    }

    /// How many settings in `category` differ from their coded default, for the tab footer's deviation indicator.
    package func settingsDiffCount(_ category: SettingsCategory) -> Int {
        switch category {
            case .general:
                return [
                    explorerPlacement != .top, treeStyle != .hierarchy, showsChangesOnly != false,
                    showsIgnoredFiles != false, syncsScrolling != true, showsMinimap != true,
                    showsStatusBar != true, autoRefresh != true
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
                    themePath != nil, lineHeightMultiple != 0, mode != .split, wrapsLines != true, wrapColumn != 0,
                    appearanceScheme != .system, badgeScheme != .classic, matchesThemeAppearance != false
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
}

// The user-defaults keys, kept outside the class body so they don't count against `type_body_length`.
extension ViewerSettings {
    enum Key {
        static let mode = "viewMode"
        static let explorerPlacement = "explorerPlacement"
        static let sidebarVisibility = "sidebarVisibility"
        static let wrapsLines = "wrapsLines"
        static let syncsScrolling = "syncsScrolling"
        static let showsChangesOnly = "showsChangesOnly"
        static let showsIgnoredFiles = "showsIgnoredFiles"
        static let autoRefresh = "autoRefresh"
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
        static let appearanceScheme = "appearanceScheme"
        static let badgeScheme = "badgeScheme"
        static let matchesThemeAppearance = "matchesThemeAppearance"
    }
}
