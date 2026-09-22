import AtelierDiagnostics
import DiffCore
import Foundation

/// The per-project override surface: adoption, the review affordance's queries, and override clearing.
/// The storage conventions (scoped keys, the registry, base fallback) live on the class next to `store`,
/// which is the other half of the same contract.
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

    /// Adopts `id` as this instance's project: every already-scoped key is re-read (falling back to the base
    /// value when the project has never overridden it), and any value that comes out different from what this
    /// instance currently holds is assigned through its normal setter, so it persists and notifies observers
    /// exactly as a manual edit would. Values change once, right after `id` resolves; nothing here rebuilds the
    /// model or the window that owns this instance.
    ///
    /// A base-default edit made afterward in the Settings window (a separate ``ViewerSettings`` instance backed
    /// by the same defaults) still reaches this window's unoverridden keys without it having to reopen: writing a
    /// base key broadcasts it (see ``baseSettingChangedNotification``), and every other instance -- this one
    /// included, whether or not it has adopted a project -- reloads it through the very same ``reload(key:)`` this
    /// method also uses, unless its own project override of that key takes precedence.
    package func adoptProject(_ id: ProjectIdentity?) {
        projectID = id
        reloadProjectScopedValues()
    }

    private func reloadProjectScopedValues() {
        for key in Self.projectScopedKeys { reload(key: key) }
    }

    /// Re-reads `key` from defaults -- resolving through ``effectiveKey(_:)`` exactly as every other read does, so
    /// a project override of `key` wins when this instance has adopted one -- and, only when that comes out
    /// different from what this instance currently holds, assigns it through the property's own setter, so it
    /// persists and notifies observers exactly as a manual edit would. Both ``adoptProject(_:)`` (by way of
    /// ``reloadProjectScopedValues()``, over every project-scoped key) and a live base-key broadcast from another
    /// instance (over just the one key that changed -- see ``baseSettingChanged(posterID:key:)``) go through this
    /// one dispatcher, so each setting's decode-and-compare logic is written once rather than twice. Split into
    /// three grouped halves purely to stay under this file's complexity budget; the grouping itself carries no
    /// meaning of its own.
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
                    .flatMap { try? JSONDecoder().decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
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
                    .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) } ?? [
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

    /// Posted (in-process only) right after this instance writes a *base* key -- one that either isn't project
    /// scoped at all, or is but this instance has no project override of its own for it -- so every other
    /// ``ViewerSettings`` instance sharing the same `UserDefaults` (one per open comparison window, plus the
    /// Settings window's own) can pick the new value up without waiting for a window to reopen. See
    /// ``adoptProject(_:)``'s own doc comment, which this replaces the known limitation on.
    nonisolated static let baseSettingChangedNotification = Notification.Name(
        "GitDiffViewer.ViewerSettings.baseSettingChanged")
    /// The `userInfo` key `baseSettingChangedNotification` carries the written key's name under.
    nonisolated static let baseSettingChangedKey = "key"

    /// The other half of `store`'s own broadcast: kept here, off the class body, purely to leave `store` itself
    /// (and the file it lives in) short.
    func postBaseSettingChanged(key: String) {
        NotificationCenter.default.post(
            name: Self.baseSettingChangedNotification, object: self, userInfo: [Self.baseSettingChangedKey: key])
    }

    /// Reacts to another ``ViewerSettings`` instance (backed by the same `UserDefaults`) having just written a
    /// base key: ignored if `posterID` turns out to be this very instance's own (its own post, echoed back by
    /// `NotificationCenter`) or if this project's own override of `key` already wins; otherwise `key` is re-read
    /// from defaults and, only if that comes out different from what this instance currently holds, assigned
    /// through its normal setter -- see ``reload(key:)``.
    ///
    /// Takes the poster's identity and the changed key rather than the `Notification` itself: extracting both
    /// `Sendable` values before crossing into `MainActor.assumeIsolated` (see `ViewerSettings.init`, where the
    /// observer is registered) keeps the non-`Sendable` `Notification` from ever crossing that boundary.
    func baseSettingChanged(posterID: ObjectIdentifier, key: String) {
        guard posterID != ObjectIdentifier(self) else { return }
        if let projectID, defaults.object(forKey: scopedKey(key, for: projectID)) != nil { return }
        isApplyingBroadcast = true
        defer { isApplyingBroadcast = false }
        reload(key: key)
    }

    /// Every project that currently overrides at least one setting in `category`, for the Settings review
    /// affordance; sorted by display path since the registry itself is unordered.
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

    /// Clears every override `projectKey` holds in `category`, leaving its overrides in other categories and
    /// every other project untouched. The project stays in the registry as long as it still overrides something
    /// anywhere; nothing here needs to know, since the registry is keyed by project, not by category. When this
    /// instance has itself adopted `projectKey` (the Settings window's review affordance clearing overrides for
    /// the very project a comparison window is showing, in the same process), its in-memory values are refreshed
    /// to match, the same way `restoreDefaults` falls back without recreating the override it just cleared.
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
