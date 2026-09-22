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

/// Whether the window chrome follows the system's own light/dark choice or is pinned to one, independent of the
/// diff theme itself -- useful when a theme's own colours read best against the window frame going the other way
/// than the system currently is.
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

    /// The project (repository root) this instance currently overlays, or nil while it still only speaks the app
    /// defaults — set once, shortly after a comparison window resolves its launch configuration's root, through
    /// ``adoptProject(_:)``.
    package internal(set) var projectID: ProjectIdentity?

    /// Settings whose value may genuinely vary from one project to the next — see docs/settings-design.md R5.
    /// Everything else (theme, layout chrome, fonts) stays a single, app-wide value no matter which window last
    /// touched it.
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

    /// Which key a read of `key` should actually hit right now: the project-scoped key once something has been
    /// written there for the adopted project, the base (app-wide) key otherwise — so a project inherits the app
    /// default until its own first override, exactly like `defaults.set`/`defaults.object` already behave for the
    /// base key alone.
    func effectiveKey(_ key: String) -> String {
        guard let projectID, Self.projectScopedKeys.contains(key) else { return key }
        let scoped = scopedKey(key, for: projectID)
        return defaults.object(forKey: scoped) != nil ? scoped : key
    }

    /// Records `id` in the cross-project registry (id → display path) the first time one of its settings is
    /// overridden, so the Settings review affordance can enumerate projects without scanning every defaults key.
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
    /// Whether the window watches the working tree and the repository's `.git` metadata for external changes
    /// (another editor's save, a `git pull` or checkout run in a terminal) and reloads on its own.
    ///
    /// Global, not project-scoped: `projectScopedKeys` below holds settings whose *right value* genuinely differs
    /// from one repository to the next (how many context lines, which tools run). Whether this window watches for
    /// outside changes isn't a property of the repository being compared — it's a workflow preference ("do I want
    /// this to update itself while I work") the user carries from one project to the next, the same way the theme
    /// or the layout chrome does, so it stays a single app-wide value like those.
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
    /// Whether the window chrome (title bar, controls, the Settings window itself) follows the system's own
    /// light/dark choice or is pinned to one. App-wide, not project-scoped, like every other piece of chrome: it
    /// describes how the app should look, not a property of any one repository.
    package var appearanceScheme: AppearanceScheme {
        didSet { store(appearanceScheme.rawValue, Key.appearanceScheme, .appearance) }
    }

    let defaults: UserDefaults

    /// Set around a block that must assign scoped properties to their (already-decoded) base value without
    /// recreating the project override that block just removed: `restoreDefaults` and clearing a project's own
    /// overrides both remove a scoped key and then run the property through its normal setter purely to update
    /// the in-memory value and notify observers, which would otherwise write straight back to the scoped key it
    /// was just cleared from.
    @ObservationIgnored private var isFallingBackToBase = false

    func applyWithoutRecreatingScopedOverrides(_ body: () -> Void) {
        isFallingBackToBase = true
        defer { isFallingBackToBase = false }
        body()
    }

    /// Set for the duration of applying a base-key change received from another instance's broadcast, so the
    /// normal setter that reload runs through doesn't turn straight around and re-broadcast the very value it was
    /// just handed -- the same discipline ``isFallingBackToBase`` uses to keep `store` from writing back to a key
    /// a caller is only reading from right now. Not `private`: ``baseSettingChanged(posterID:key:)`` (in
    /// `ViewerSettings+ProjectOverrides.swift`, alongside every other reload path) needs it too.
    @ObservationIgnored var isApplyingBroadcast = false
    /// `nonisolated(unsafe)`: only ever written once, at the end of `init`, and read once, in `deinit` -- which,
    /// unlike every other member here, cannot itself be `@MainActor`-isolated -- to remove the very same token.
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

    /// Resets every setting in `category` to its coded default, going through the same setters as a user edit so
    /// each one stores to user defaults and fires its observers exactly as it would for a manual change.
    ///
    /// For a scoped setting, "restore defaults" means something different once a project has been adopted: rather
    /// than force every project back to the coded default, it clears this project's own override and falls back
    /// to whatever the base (app-wide) value currently is -- the same thing turning the override off by hand
    /// would leave behind. A project-less instance (the Settings window itself) still resets straight to the
    /// coded default, exactly as before.
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

    /// How many settings in `category` currently differ from their coded default, for the tab footer's subtle
    /// deviation indicator (P6): cheap enough to recompute on every render since each category is a handful of
    /// comparisons.
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
                    appearanceScheme != .system
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
    }
}
