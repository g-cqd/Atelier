import AtelierDiagnostics
import DiffCore
import Foundation

/// The per-project override surface: adoption, cross-instance reloads, the known projects, and override clearing.
extension ViewerSettings {
    /// The settings of `category`'s tab that can differ from one project to the next (decision D11): what a
    /// comparison shows and how, and the tools. What stays app-wide is how the app itself looks and is arranged:
    /// the appearance, theme matching and badge colors D11 names, and with them the color scheme, the line height,
    /// the explorers' placement, synced scrolling and the status bar.
    static func scopedKeys(for category: SettingsCategory) -> Set<String> {
        switch category {
            case .general:
                [Key.showsChangesOnly, Key.showsIgnoredFiles, Key.treeStyle, Key.showsMinimap, Key.autoRefresh]
            case .diff: [Key.isolatesChanges, Key.contextLines, Key.granularity, Key.diffHeuristics]
            case .appearance: [Key.mode, Key.wrapsLines, Key.wrapColumn]
            case .tools:
                [
                    Key.diagnosticsEnabled, Key.showsHoverDocumentation, Key.analyzedSides, Key.toolLocations,
                    Key.lspServerLocations
                ]
        }
    }

    /// Each setting's defaults key by property, for the views that ask whether a control edits a project's value.
    private static let keysByProperty: [PartialKeyPath<ViewerSettings>: String] = [
        \.mode: Key.mode, \.explorerPlacement: Key.explorerPlacement, \.wrapsLines: Key.wrapsLines,
        \.syncsScrolling: Key.syncsScrolling, \.showsChangesOnly: Key.showsChangesOnly,
        \.showsIgnoredFiles: Key.showsIgnoredFiles, \.autoRefresh: Key.autoRefresh, \.granularity: Key.granularity,
        \.diffHeuristics: Key.diffHeuristics, \.showsMinimap: Key.showsMinimap, \.showsStatusBar: Key.showsStatusBar,
        \.treeStyle: Key.treeStyle, \.wrapColumn: Key.wrapColumn, \.themePath: Key.themePath,
        \.lineHeightMultiple: Key.lineHeightMultiple, \.contextLines: Key.contextLines,
        \.isolatesChanges: Key.isolatesChanges, \.diagnosticsEnabled: Key.diagnosticsEnabled,
        \.showsHoverDocumentation: Key.showsHoverDocumentation, \.toolLocations: Key.toolLocations,
        \.lspServerLocations: Key.lspServerLocations, \.analyzedSides: Key.analyzedSides,
        \.appearanceScheme: Key.appearanceScheme, \.badgeScheme: Key.badgeScheme,
        \.matchesThemeAppearance: Key.matchesThemeAppearance
    ]

    /// Whether the setting behind `property` can differ per project; the Settings window greys out the others while
    /// it edits a project, since they apply to every project alike.
    package static func isProjectScoped(_ property: PartialKeyPath<ViewerSettings>) -> Bool {
        keysByProperty[property].map(projectScopedKeys.contains) ?? false
    }

    /// Adopts `id` as this instance's project and re-reads every scoped key, so each value that changes goes
    /// through its setter and reaches observers as a manual edit would, without being written back: adopting a
    /// project creates no override. The project joins the known projects the Settings window lists. Nothing
    /// rebuilds the model or its window.
    package func adoptProject(_ id: ProjectIdentity?) {
        projectID = id
        if let id { rememberProject(id) }
        applyingStoredValues { reloadProjectScopedValues() }
    }

    private func reloadProjectScopedValues() {
        for key in Self.projectScopedKeys { reload(key: key) }
    }

    /// Re-reads `key` through ``effectiveKey(_:)`` and assigns it through its setter only when the value changed.
    /// The three groups exist only to stay under the complexity budget.
    func reload(key: String) {
        if reloadLayoutSetting(key) { return }
        if reloadDiffSetting(key) { return }
        if reloadDiagnosticsSetting(key) { return }
    }

    private func reloadLayoutSetting(_ key: String) -> Bool {
        switch key {
            case Key.mode:
                let value = defaults.string(forKey: effectiveKey(key)).flatMap(ViewMode.init(rawValue:)) ?? .split
                if value != mode { mode = value }
            case Key.explorerPlacement:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(ExplorerPlacement.init(rawValue:)) ?? .top
                if value != explorerPlacement { explorerPlacement = value }
            case Key.sidebarVisibility:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(SidebarVisibility.init(rawValue:)) ?? .all
                if value != sidebarVisibility { sidebarVisibility = value }
            case Key.wrapsLines:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != wrapsLines { wrapsLines = value }
            case Key.syncsScrolling:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != syncsScrolling { syncsScrolling = value }
            case Key.autoRefresh:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != autoRefresh { autoRefresh = value }
            case Key.showsMinimap:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != showsMinimap { showsMinimap = value }
            case Key.showsStatusBar:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != showsStatusBar { showsStatusBar = value }
            case Key.appearanceScheme:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(AppearanceScheme.init(rawValue:)) ?? .system
                if value != appearanceScheme { appearanceScheme = value }
            case Key.badgeScheme:
                let value = defaults.string(forKey: effectiveKey(key)).flatMap(BadgeScheme.init(rawValue:)) ?? .classic
                if value != badgeScheme { badgeScheme = value }
            case Key.matchesThemeAppearance:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? false
                if value != matchesThemeAppearance { matchesThemeAppearance = value }
            default:
                return false
        }
        return true
    }

    private func reloadDiffSetting(_ key: String) -> Bool {
        switch key {
            case Key.showsChangesOnly:
                let value = defaults.bool(forKey: effectiveKey(key))
                if value != showsChangesOnly { showsChangesOnly = value }
            case Key.showsIgnoredFiles:
                let value = defaults.bool(forKey: effectiveKey(key))
                if value != showsIgnoredFiles { showsIgnoredFiles = value }
            case Key.granularity:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(IntralineGranularity.init(rawValue:))
                    ?? .word
                if value != granularity { granularity = value }
            case Key.diffHeuristics:
                let value =
                    defaults.data(forKey: effectiveKey(key))
                    .flatMap { try? DefaultsJSON.decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
                if value != diffHeuristics { diffHeuristics = value }
            case Key.treeStyle:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(FileTreeStyle.init(rawValue:)) ?? .hierarchy
                if value != treeStyle { treeStyle = value }
            case Key.wrapColumn:
                let value = defaults.integer(forKey: effectiveKey(key))
                if value != wrapColumn { wrapColumn = value }
            case Key.themePath:
                let value = defaults.string(forKey: effectiveKey(key))
                if value != themePath { themePath = value }
            case Key.lineHeightMultiple:
                let value = defaults.double(forKey: effectiveKey(key))
                if value != lineHeightMultiple { lineHeightMultiple = value }
            case Key.contextLines:
                let value = defaults.object(forKey: effectiveKey(key)) as? Int ?? 3
                if value != contextLines { contextLines = value }
            case Key.isolatesChanges:
                let value = defaults.bool(forKey: effectiveKey(key))
                if value != isolatesChanges { isolatesChanges = value }
            default:
                return false
        }
        return true
    }

    private func reloadDiagnosticsSetting(_ key: String) -> Bool {
        switch key {
            case Key.diagnosticsEnabled:
                let value = defaults.bool(forKey: effectiveKey(key))
                if value != diagnosticsEnabled { diagnosticsEnabled = value }
            case Key.showsHoverDocumentation:
                let value = defaults.object(forKey: effectiveKey(key)) as? Bool ?? true
                if value != showsHoverDocumentation { showsHoverDocumentation = value }
            case Key.toolLocations:
                let value = Self.decodeToolLocations(defaults.data(forKey: effectiveKey(key)))
                if value != toolLocations { toolLocations = value }
            case Key.lspServerLocations:
                let value =
                    defaults.data(forKey: effectiveKey(key))
                    .flatMap { try? DefaultsJSON.decode([String: ToolLocation].self, from: $0) } ?? [
                        "sourcekit-lsp": ToolLocation()
                    ]
                if value != lspServerLocations { lspServerLocations = value }
            case Key.analyzedSides:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(AnalyzedSides.init(rawValue:)) ?? .newer
                if value != analyzedSides { analyzedSides = value }
            case Key.settingsPane:
                let value =
                    defaults.string(forKey: effectiveKey(key)).flatMap(SettingsPane.init(rawValue:)) ?? .general
                if value != settingsPane { settingsPane = value }
            default:
                return false
        }
        return true
    }

    // MARK: - Broadcasts

    /// Posted in-process after an instance writes a key, so every other instance sharing its `UserDefaults` picks up
    /// the new value without its window reopening.
    nonisolated static let settingChangedNotification = Notification.Name(
        "GitDiffViewer.ViewerSettings.settingChanged")
    /// The `userInfo` key `settingChangedNotification` carries the written key's name under.
    nonisolated static let settingChangedKey = "key"
    /// The `userInfo` key naming the project whose override was written or cleared; absent for a base write.
    nonisolated static let settingChangedProjectKey = "project"

    /// Tells every other instance that this one wrote `key`: the base key when `projectKey` is nil, that project's
    /// override of it otherwise.
    func postSettingChanged(key: String, projectKey: String?) {
        var userInfo = [Self.settingChangedKey: key]
        if let projectKey { userInfo[Self.settingChangedProjectKey] = projectKey }
        NotificationCenter.default.post(name: Self.settingChangedNotification, object: self, userInfo: userInfo)
        if projectKey != nil { postProjectsChanged() }
    }

    /// Reloads a key another instance just wrote: a base key, unless this instance's project override of `key`
    /// wins; a project's override, only in an instance on that project. The value is only read, never written back,
    /// so a broadcast neither re-broadcasts nor creates an override. Takes `Sendable` values because the
    /// `Notification` itself must not cross into `MainActor.assumeIsolated`.
    func settingChanged(posterID: ObjectIdentifier, key: String, projectKey: String?) {
        guard posterID != ObjectIdentifier(self) else { return }
        if let projectKey {
            guard projectID?.key == projectKey else { return }
        } else if let projectID, defaults.object(forKey: scopedKey(key, for: projectID)) != nil {
            return
        }
        applyingStoredValues { reload(key: key) }
    }

    // MARK: - Known projects

    /// The defaults key of every project a window adopted, key to display path, whether or not it overrides anything.
    static let knownProjectsKey = "knownProjects"

    /// Posted in-process whenever a project becomes known, or one of its overrides is written or cleared, so the
    /// Settings window's list follows.
    nonisolated static let projectsChangedNotification = Notification.Name(
        "GitDiffViewer.ViewerSettings.projectsChanged")

    func postProjectsChanged() {
        NotificationCenter.default.post(name: Self.projectsChangedNotification, object: self)
    }

    /// Records `id` among the known projects. Knowing a project is not overriding anything: the override registry and
    /// "overridden in N projects" only count what the user changed.
    private func rememberProject(_ id: ProjectIdentity) {
        var known = (defaults.dictionary(forKey: Self.knownProjectsKey) as? [String: String]) ?? [:]
        guard known[id.key] != id.displayPath else { return }
        known[id.key] = id.displayPath
        defaults.set(known, forKey: Self.knownProjectsKey)
        postProjectsChanged()
    }

    /// Every project the app knows of, a window's or one with overrides, sorted by name and then by path.
    package var knownProjects: [ProjectIdentity] {
        let known = (defaults.dictionary(forKey: Self.knownProjectsKey) as? [String: String]) ?? [:]
        let registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        return Set(known.values).union(registry.values)
            .map { ProjectIdentity(root: URL(filePath: $0, directoryHint: .isDirectory)) }
            .sorted { ($0.name, $0.displayPath) < ($1.name, $1.displayPath) }
    }

    /// The keys `projectKey` overrides, in the order the Settings tabs show them.
    package func overriddenKeys(projectKey: String) -> [String] {
        Self.orderedScopedKeys.filter { defaults.object(forKey: Self.scopedKey($0, projectKey: projectKey)) != nil }
    }

    /// Every scoped key, tab by tab.
    static var orderedScopedKeys: [String] {
        SettingsCategory.allCases.flatMap { scopedKeys(for: $0).sorted() }
    }

    // MARK: - Overrides

    /// Every project that overrides at least one setting in `category`, sorted by display path.
    package func projectsWithOverrides(in category: SettingsCategory) -> [(key: String, displayPath: String)] {
        let keys = Self.scopedKeys(for: category)
        guard !keys.isEmpty else { return [] }
        let registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        return
            registry
            .filter { entry in
                keys.contains { defaults.object(forKey: Self.scopedKey($0, projectKey: entry.key)) != nil }
            }
            .map { (key: $0.key, displayPath: $0.value) }
            .sorted { $0.displayPath < $1.displayPath }
    }

    /// Removes `projectKey`'s override of `key`, if it has one, and tells every instance on that project, which falls
    /// back to the app-wide value; the project leaves the override registry once it overrides nothing.
    package func clearOverride(_ key: String, projectKey: String) {
        let scoped = Self.scopedKey(key, projectKey: projectKey)
        guard defaults.object(forKey: scoped) != nil else { return }
        defaults.removeObject(forKey: scoped)
        pruneRegistryIfFullyCleared(projectKey: projectKey)
        postSettingChanged(key: key, projectKey: projectKey)
    }

    /// Clears every override `projectKey` holds in `category`. An instance that adopted `projectKey` refreshes its
    /// in-memory values to match.
    package func clearOverrides(projectKey: String, category: SettingsCategory) {
        for key in Self.scopedKeys(for: category) { clearOverride(key, projectKey: projectKey) }
        refreshIfAdopted(projectKey)
    }

    /// Clears every override `projectKey` holds in any category; the project stays known.
    package func clearAllOverrides(projectKey: String) {
        for key in Self.projectScopedKeys { clearOverride(key, projectKey: projectKey) }
        refreshIfAdopted(projectKey)
    }

    /// Clears every override `projectKey` holds and forgets the project, until a window adopts it again.
    package func forgetProject(projectKey: String) {
        clearAllOverrides(projectKey: projectKey)
        for registryKey in [Self.knownProjectsKey, Self.projectRegistryKey] {
            var entries = (defaults.dictionary(forKey: registryKey) as? [String: String]) ?? [:]
            guard entries.removeValue(forKey: projectKey) != nil else { continue }
            defaults.set(entries, forKey: registryKey)
        }
        postProjectsChanged()
    }

    private func refreshIfAdopted(_ projectKey: String) {
        guard projectID?.key == projectKey else { return }
        applyingStoredValues { reloadProjectScopedValues() }
    }

    private func pruneRegistryIfFullyCleared(projectKey: String) {
        let stillOverrides = Self.projectScopedKeys.contains {
            defaults.object(forKey: Self.scopedKey($0, projectKey: projectKey)) != nil
        }
        guard !stillOverrides else { return }
        var registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        guard registry.removeValue(forKey: projectKey) != nil else { return }
        defaults.set(registry, forKey: Self.projectRegistryKey)
    }
}
