import AtelierDiagnostics
import DiffCore
import Foundation

/// The per-project override surface: adoption, cross-instance reloads, the Settings queries, and override clearing.
extension ViewerSettings {
    /// The subset of `projectScopedKeys` a given Settings tab shows, for the "overridden in N projects" footer.
    static func scopedKeys(for category: SettingsCategory) -> Set<String> {
        switch category {
            case .general: [Key.showsChangesOnly, Key.showsIgnoredFiles, Key.treeStyle]
            case .diff: [Key.contextLines, Key.diffHeuristics]
            case .appearance: []
            case .tools: [Key.diagnosticsEnabled, Key.analyzedSides, Key.toolLocations, Key.lspServerLocations]
        }
    }

    /// Adopts `id` as this instance's project and re-reads every scoped key, so each value that changes goes
    /// through its setter exactly as a manual edit would. Nothing rebuilds the model or its window.
    package func adoptProject(_ id: ProjectIdentity?) {
        projectID = id
        reloadProjectScopedValues()
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

    /// Posted in-process after an instance writes a base key, so every other instance sharing its `UserDefaults`
    /// picks up the new value without its window reopening.
    nonisolated static let baseSettingChangedNotification = Notification.Name(
        "GitDiffViewer.ViewerSettings.baseSettingChanged")
    /// The `userInfo` key `baseSettingChangedNotification` carries the written key's name under.
    nonisolated static let baseSettingChangedKey = "key"

    /// Tells every other instance that this one wrote the base `key`.
    func postBaseSettingChanged(key: String) {
        NotificationCenter.default.post(
            name: Self.baseSettingChangedNotification, object: self, userInfo: [Self.baseSettingChangedKey: key])
    }

    /// Reloads a base key another instance just wrote, unless this instance's project override of `key` wins. Takes
    /// `Sendable` values because the `Notification` itself must not cross into `MainActor.assumeIsolated`.
    func baseSettingChanged(posterID: ObjectIdentifier, key: String) {
        guard posterID != ObjectIdentifier(self) else { return }
        if let projectID, defaults.object(forKey: scopedKey(key, for: projectID)) != nil { return }
        isApplyingBroadcast = true
        defer { isApplyingBroadcast = false }
        reload(key: key)
    }

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

    /// Clears every override `projectKey` holds in `category`; the project leaves the registry once it overrides
    /// nothing. An instance that adopted `projectKey` refreshes its in-memory values to match.
    package func clearOverrides(projectKey: String, category: SettingsCategory) {
        for key in Self.scopedKeys(for: category) {
            defaults.removeObject(forKey: Self.scopedKey(key, projectKey: projectKey))
        }
        pruneRegistryIfFullyCleared(projectKey: projectKey)
        refreshIfAdopted(projectKey)
    }

    /// Clears every override `projectKey` holds in any category, and drops it from the registry.
    package func clearAllOverrides(projectKey: String) {
        for key in Self.projectScopedKeys {
            defaults.removeObject(forKey: Self.scopedKey(key, projectKey: projectKey))
        }
        var registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        registry.removeValue(forKey: projectKey)
        defaults.set(registry, forKey: Self.projectRegistryKey)
        refreshIfAdopted(projectKey)
    }

    private func refreshIfAdopted(_ projectKey: String) {
        guard projectID?.key == projectKey else { return }
        applyWithoutRecreatingScopedOverrides { reloadProjectScopedValues() }
    }

    private func pruneRegistryIfFullyCleared(projectKey: String) {
        let stillOverrides = Self.projectScopedKeys.contains {
            defaults.object(forKey: Self.scopedKey($0, projectKey: projectKey)) != nil
        }
        guard !stillOverrides else { return }
        var registry = (defaults.dictionary(forKey: Self.projectRegistryKey) as? [String: String]) ?? [:]
        registry.removeValue(forKey: projectKey)
        defaults.set(registry, forKey: Self.projectRegistryKey)
    }
}
