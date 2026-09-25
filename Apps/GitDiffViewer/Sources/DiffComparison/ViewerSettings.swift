package import AtelierDiagnostics
package import DiffCore
import DiffGit
package import DiffRendering
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

/// Which sides of a comparison the analyzers run on (DIAG-08, decision D12). Each analyzed side runs on its own
/// files, a git ref exported first, and its findings show on its own rows only.
package enum AnalyzedSides: String, CaseIterable, Identifiable, Codable {
    case both
    /// The left, older side only.
    case leftOnly = "left"
    /// The right, newer side only, which is the default.
    case rightOnly = "right"
    case none

    package var id: String { rawValue }

    /// Reads a stored value, the two values of the older setting included: "newer" analyzed the right side only, and
    /// "both" still means both, now each side on its own files rather than the right side's findings echoed left.
    package init?(storedValue: String) {
        if storedValue == "newer" {
            self = .rightOnly
        } else {
            self.init(rawValue: storedValue)
        }
    }

    /// Whether the left side is analyzed.
    package var includesLeft: Bool { self == .both || self == .leftOnly }
    /// Whether the right side is analyzed.
    package var includesRight: Bool { self == .both || self == .rightOnly }
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
    /// Every known project, with what it overrides.
    case projects

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

    /// Settings whose value may vary from one project to the next, every tab's ``scopedKeys(for:)``; everything
    /// else stays app-wide.
    static let projectScopedKeys: Set<String> = SettingsCategory.allCases.reduce(into: []) { keys, category in
        keys.formUnion(scopedKeys(for: category))
    }

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

    // Every setter returns early on an equal value: re-selecting what is already chosen must neither write an
    // override nobody made nor tell observers to redo work.
    package var mode: ViewMode {
        didSet {
            guard mode != oldValue else { return }
            store(mode.rawValue, Key.mode, (oldValue == .inline) != (mode == .inline) ? .layout : .appearance)
        }
    }
    package var explorerPlacement: ExplorerPlacement {
        didSet {
            if explorerPlacement != oldValue { store(explorerPlacement.rawValue, Key.explorerPlacement, .appearance) }
        }
    }
    /// This window's sidebar, stored for the next window but never shared with the open ones (``windowLocalKeys``).
    package var sidebarVisibility: SidebarVisibility {
        didSet {
            if sidebarVisibility != oldValue { store(sidebarVisibility.rawValue, Key.sidebarVisibility, .appearance) }
        }
    }
    package var wrapsLines: Bool {
        didSet { if wrapsLines != oldValue { store(wrapsLines, Key.wrapsLines, .appearance) } }
    }
    /// Keep the two panes of a split layout at the same vertical position.
    package var syncsScrolling: Bool {
        didSet { if syncsScrolling != oldValue { store(syncsScrolling, Key.syncsScrolling, .appearance) } }
    }
    package var showsChangesOnly: Bool {
        didSet { if showsChangesOnly != oldValue { store(showsChangesOnly, Key.showsChangesOnly, .trees) } }
    }
    /// Lists the files git ignores in a section of their own, so their content can be looked at on demand.
    package var showsIgnoredFiles: Bool {
        didSet { if showsIgnoredFiles != oldValue { store(showsIgnoredFiles, Key.showsIgnoredFiles, .trees) } }
    }
    /// Splits the merged sidebar's flat list into a section per commit when the left side is an ancestor of the right
    /// in one repository (GIT-06); ``CommitGroupingEligibility`` says when it applies.
    package var groupsByCommit: Bool {
        didSet { if groupsByCommit != oldValue { store(groupsByCommit, Key.groupsByCommit, .trees) } }
    }
    /// Whether the window watches the working tree and the repository's `.git` metadata for external changes and
    /// reloads on its own.
    package var autoRefresh: Bool {
        didSet { if autoRefresh != oldValue { store(autoRefresh, Key.autoRefresh, .freshness) } }
    }
    package var granularity: IntralineGranularity {
        didSet { if granularity != oldValue { store(granularity.rawValue, Key.granularity, .diff) } }
    }
    /// Which diff heuristics are wired in; any change re-diffs the selection.
    package var diffHeuristics: DiffHeuristics {
        didSet {
            if diffHeuristics != oldValue { store(try? DefaultsJSON.encode(diffHeuristics), Key.diffHeuristics, .diff) }
        }
    }
    package var showsMinimap: Bool {
        didSet { if showsMinimap != oldValue { store(showsMinimap, Key.showsMinimap, .appearance) } }
    }
    package var showsStatusBar: Bool {
        didSet { if showsStatusBar != oldValue { store(showsStatusBar, Key.showsStatusBar, .appearance) } }
    }
    package var treeStyle: FileTreeStyle {
        didSet { if treeStyle != oldValue { store(treeStyle.rawValue, Key.treeStyle, .trees) } }
    }
    /// Characters per line when wrapping; zero wraps at the viewport width.
    package var wrapColumn: Int {
        didSet { if wrapColumn != oldValue { store(wrapColumn, Key.wrapColumn, .appearance) } }
    }
    /// Path of the Xcode theme file to derive colors and font from; nil keeps the system look.
    package var themePath: String? { didSet { if themePath != oldValue { store(themePath, Key.themePath, .palette) } } }
    /// Whether the inline layout shows the new file alone, with a gutter marker at each change that discloses it in
    /// place (book DIFF-04). Off by default; nothing changes in the other layouts.
    package var compactsInlineView: Bool {
        didSet {
            guard compactsInlineView != oldValue else { return }
            store(compactsInlineView, Key.compactsInlineView, mode == .inline ? .layout : .appearance)
        }
    }
    /// Show only the changed regions with context, in every layout.
    package var isolatesChanges: Bool {
        didSet { if isolatesChanges != oldValue { store(isolatesChanges, Key.isolatesChanges, .layout) } }
    }
    /// Unchanged rows kept around each change when changes are isolated.
    package var contextLines: Int {
        didSet { if contextLines != oldValue { store(contextLines, Key.contextLines, .layout) } }
    }
    /// Line height as a multiple of the font's; zero follows the theme (1.0 for the system palette).
    package var lineHeightMultiple: Double {
        didSet { if lineHeightMultiple != oldValue { store(lineHeightMultiple, Key.lineHeightMultiple, .layout) } }
    }
    /// Master toggle for the diagnostics track; off cancels any run in flight and clears findings.
    package var diagnosticsEnabled: Bool {
        didSet { if diagnosticsEnabled != oldValue { store(diagnosticsEnabled, Key.diagnosticsEnabled, .diagnostics) } }
    }
    /// Whether hovering a symbol shows its documentation.
    package var showsHoverDocumentation: Bool {
        didSet {
            if showsHoverDocumentation != oldValue {
                store(showsHoverDocumentation, Key.showsHoverDocumentation, .appearance)
            }
        }
    }
    /// What the hover panel is made of, Liquid Glass by default (book HOVER-08); the next panel shown follows a
    /// change, and one already open keeps its material until it shows another document.
    package var hoverPanelMaterial: HoverPanelMaterial {
        didSet {
            if hoverPanelMaterial != oldValue {
                store(hoverPanelMaterial.rawValue, Key.hoverPanelMaterial, .appearance)
            }
        }
    }
    /// Per-tool enablement and custom executable path, keyed by tool; every tool is enabled by default.
    package var toolLocations: [DiagnosticTool: ToolLocation] {
        didSet {
            guard toolLocations != oldValue else { return }
            let encoded = Dictionary(uniqueKeysWithValues: toolLocations.map { ($0.key.rawValue, $0.value) })
            store(try? DefaultsJSON.encode(encoded), Key.toolLocations, .diagnostics)
        }
    }
    /// Per-server overrides for language servers outside ``DiagnosticTool``, such as `sourcekit-lsp`, by server id.
    package var lspServerLocations: [String: ToolLocation] {
        didSet {
            guard lspServerLocations != oldValue else { return }
            store(try? DefaultsJSON.encode(lspServerLocations), Key.lspServerLocations, .diagnostics)
        }
    }
    /// Which side(s) of a comparison diagnostics findings are mapped onto.
    package var analyzedSides: AnalyzedSides {
        didSet { if analyzedSides != oldValue { store(analyzedSides.rawValue, Key.analyzedSides, .diagnostics) } }
    }
    /// The Settings window's last-viewed tab, restored the next time it opens.
    package var settingsPane: SettingsPane {
        didSet { if settingsPane != oldValue { store(settingsPane.rawValue, Key.settingsPane, .appearance) } }
    }
    /// The light/dark appearance of the window chrome, the Settings window included.
    package var appearanceScheme: AppearanceScheme {
        didSet {
            if appearanceScheme != oldValue { store(appearanceScheme.rawValue, Key.appearanceScheme, .appearance) }
        }
    }
    /// Which colours a change badge's letter is drawn in: classic red/green/orange/purple, or Xcode's own.
    /// The colours a diff's changes take, the app's red and green or Xcode's gray and blue (book D18).
    package var diffColors: DiffColors {
        didSet { if diffColors != oldValue { store(diffColors.rawValue, Key.diffColors, .palette) } }
    }
    package var badgeScheme: BadgeScheme {
        didSet { if badgeScheme != oldValue { store(badgeScheme.rawValue, Key.badgeScheme, .appearance) } }
    }
    /// Whether the window follows the selected theme's own light/dark background instead of the system's, when
    /// ``appearanceScheme`` is ``AppearanceScheme/system`` -- an explicit light/dark pin always wins.
    package var matchesThemeAppearance: Bool {
        didSet {
            if matchesThemeAppearance != oldValue {
                store(matchesThemeAppearance, Key.matchesThemeAppearance, .appearance)
            }
        }
    }

    /// Whether the code panes, the single file's and the cards', rubber-band past their edges; the card list keeps its
    /// own bounce either way (book SET-09, D25).
    package var bouncesAtEdges: Bool {
        didSet { if bouncesAtEdges != oldValue { store(bouncesAtEdges, Key.bouncesAtEdges, .appearance) } }
    }
    /// Whether a file pane scrolls on past its last line until that line reaches its top, rather than stopping with
    /// it at its bottom (book CARD-19).
    package var scrollsPastEnd: Bool {
        didSet { if scrollsPastEnd != oldValue { store(scrollsPastEnd, Key.scrollsPastEnd, .appearance) } }
    }
    /// Whether a file opens scrolled to its first change rather than at its top (book DIFF-08). A file tab that comes
    /// back to where it was left, and a file that fits its pane, are not scrolled to it either way.
    package var scrollsToFirstChange: Bool {
        didSet {
            if scrollsToFirstChange != oldValue { store(scrollsToFirstChange, Key.scrollsToFirstChange, .appearance) }
        }
    }

    /// Whether a Swift side's colour is refined with swift-syntax once the lexer's has shown (PERF-11); on by default.
    package var refinesSwiftColor: Bool {
        didSet { if refinesSwiftColor != oldValue { store(refinesSwiftColor, Key.refinesSwiftColor, .appearance) } }
    }

    let defaults: UserDefaults

    /// Set while scoped properties are reassigned their base value after their override was removed, so `store`
    /// notifies observers without writing the override back.
    @ObservationIgnored private var isFallingBackToBase = false

    func applyWithoutRecreatingScopedOverrides(_ body: () -> Void) {
        let outer = isFallingBackToBase
        isFallingBackToBase = true
        defer { isFallingBackToBase = outer }
        body()
    }

    /// Set while properties are reassigned values read back from storage: another instance's base write, or the
    /// values of a project this instance adopts. `store` then writes nothing, neither the project's key, which would
    /// turn a value the user never chose there into an override, nor the base key, which already holds it, and so
    /// broadcasts nothing either; observers still hear the change.
    @ObservationIgnored private var isApplyingStoredValues = false

    func applyingStoredValues(_ body: () -> Void) {
        let outer = isApplyingStoredValues
        isApplyingStoredValues = true
        defer { isApplyingStoredValues = outer }
        body()
    }

    /// `nonisolated(unsafe)`: written once at the end of `init` and read once in the nonisolated `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var settingObserver: (any NSObjectProtocol)?

    private func store(_ value: Any?, _ key: String, _ change: Change) {
        if !isApplyingStoredValues { write(value, key) }
        observers.removeAll { $0.owner.object == nil }
        for observer in observers { observer.handler(change) }
    }

    /// Settings each window keeps for itself: stored so the next window opens as the last one was left, never
    /// announced to the others, so hiding the sidebar in one window leaves every other window's alone.
    static let windowLocalKeys: Set<String> = [Key.sidebarVisibility]

    /// Writes a user's edit to the adopted project's key for a scoped setting, to the base key otherwise, and
    /// announces it to every other instance, so each window on that project, or on none that overrides the key,
    /// follows at once; a window-local setting is only stored.
    private func write(_ value: Any?, _ key: String) {
        guard let projectID, Self.projectScopedKeys.contains(key) else {
            defaults.set(value, forKey: key)
            if !Self.windowLocalKeys.contains(key) { postSettingChanged(key: key, projectKey: nil) }
            return
        }
        guard !isFallingBackToBase else { return }
        defaults.set(value, forKey: scopedKey(key, for: projectID))
        registerProject(projectID)
        postSettingChanged(key: key, projectKey: projectID.key)
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
        groupsByCommit = defaults.bool(forKey: Key.groupsByCommit)
        autoRefresh = defaults.object(forKey: Key.autoRefresh) as? Bool ?? true
        granularity = defaults.string(forKey: Key.granularity).flatMap(IntralineGranularity.init(rawValue:)) ?? .word
        diffHeuristics =
            defaults.data(forKey: Key.diffHeuristics)
            .flatMap { try? DefaultsJSON.decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
        showsMinimap = defaults.object(forKey: Key.showsMinimap) as? Bool ?? true
        showsStatusBar = defaults.object(forKey: Key.showsStatusBar) as? Bool ?? true
        treeStyle = Self.storedTreeStyle(defaults, key: Key.treeStyle)
        wrapColumn = defaults.integer(forKey: Key.wrapColumn)
        themePath = defaults.string(forKey: Key.themePath)
        lineHeightMultiple = defaults.double(forKey: Key.lineHeightMultiple)
        contextLines = defaults.object(forKey: Key.contextLines) as? Int ?? 3
        isolatesChanges = defaults.bool(forKey: Key.isolatesChanges)
        compactsInlineView = defaults.bool(forKey: Key.compactsInlineView)
        diagnosticsEnabled = defaults.bool(forKey: Key.diagnosticsEnabled)
        showsHoverDocumentation = defaults.object(forKey: Key.showsHoverDocumentation) as? Bool ?? true
        hoverPanelMaterial =
            defaults.string(forKey: Key.hoverPanelMaterial).flatMap(HoverPanelMaterial.init(rawValue:)) ?? .liquidGlass
        toolLocations = Self.decodeToolLocations(defaults.data(forKey: Key.toolLocations))
        lspServerLocations =
            defaults.data(forKey: Key.lspServerLocations)
            .flatMap { try? DefaultsJSON.decode([String: ToolLocation].self, from: $0) }
            ?? ["sourcekit-lsp": ToolLocation()]
        analyzedSides =
            defaults.string(forKey: Key.analyzedSides).flatMap(AnalyzedSides.init(storedValue:)) ?? .rightOnly
        settingsPane =
            defaults.string(forKey: Key.settingsPane).flatMap(SettingsPane.init(rawValue:)) ?? .general
        appearanceScheme =
            defaults.string(forKey: Key.appearanceScheme).flatMap(AppearanceScheme.init(rawValue:)) ?? .system
        badgeScheme = defaults.string(forKey: Key.badgeScheme).flatMap(BadgeScheme.init(rawValue:)) ?? .classic
        diffColors = defaults.string(forKey: Key.diffColors).flatMap(DiffColors.init(rawValue:)) ?? .standard
        matchesThemeAppearance = defaults.object(forKey: Key.matchesThemeAppearance) as? Bool ?? false
        bouncesAtEdges = defaults.bool(forKey: Key.bouncesAtEdges)
        scrollsPastEnd = defaults.bool(forKey: Key.scrollsPastEnd)
        scrollsToFirstChange = defaults.object(forKey: Key.scrollsToFirstChange) as? Bool ?? true
        refinesSwiftColor = defaults.object(forKey: Key.refinesSwiftColor) as? Bool ?? true
        settingObserver = NotificationCenter.default.addObserver(
            forName: Self.settingChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let poster = notification.object else { return }
            guard let key = notification.userInfo?[Self.settingChangedKey] as? String else { return }
            let projectKey = notification.userInfo?[Self.settingChangedProjectKey] as? String
            let posterID = ObjectIdentifier(poster as AnyObject)
            MainActor.assumeIsolated { self?.settingChanged(posterID: posterID, key: key, projectKey: projectKey) }
        }
    }

    deinit {
        if let settingObserver { NotificationCenter.default.removeObserver(settingObserver) }
    }
}

// The user-defaults keys, kept outside the class body so they don't count against `type_body_length`.
extension ViewerSettings {
    /// The tree style stored under `key`, or, with none there, the one the older `compactsFolders` flag stood for, so
    /// every reader of the setting, adopting a project or restoring one included, keeps the flag's meaning.
    static func storedTreeStyle(_ defaults: UserDefaults, key: String) -> FileTreeStyle {
        defaults.string(forKey: key).flatMap(FileTreeStyle.init(rawValue:))
            ?? (defaults.bool(forKey: Key.compactsFolders) ? .compact : .hierarchy)
    }

    enum Key {
        static let mode = "viewMode"
        static let explorerPlacement = "explorerPlacement"
        static let sidebarVisibility = "sidebarVisibility"
        static let wrapsLines = "wrapsLines"
        static let syncsScrolling = "syncsScrolling"
        static let showsChangesOnly = "showsChangesOnly"
        static let showsIgnoredFiles = "showsIgnoredFiles"
        static let groupsByCommit = "groupsByCommit"
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
        static let compactsInlineView = "compactsInlineView"
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let showsHoverDocumentation = "hoverDocumentation"
        static let hoverPanelMaterial = "hoverPanelMaterial"
        static let toolLocations = "diagnosticToolLocations"
        static let lspServerLocations = "lspServerLocations"
        static let analyzedSides = "analyzedSides"
        static let settingsPane = "settingsPane"
        static let appearanceScheme = "appearanceScheme"
        static let badgeScheme = "badgeScheme"
        static let diffColors = "diffColors"
        static let matchesThemeAppearance = "matchesThemeAppearance"
        static let bouncesAtEdges = "bouncesAtEdges"
        static let scrollsPastEnd = "scrollsPastEnd"
        static let scrollsToFirstChange = "scrollsToFirstChange"
        static let refinesSwiftColor = "refinesSwiftColor"
    }
}
