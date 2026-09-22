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
    /// Known limitation: base-default edits made afterward in the Settings window (a separate ``ViewerSettings``
    /// instance, per docs/settings-design.md R5) do not live-propagate into an already-open, already-adopted
    /// window's unoverridden keys — the window would need to reopen, or a future revision would need a
    /// defaults-change observer bridging the two instances.
    package func adoptProject(_ id: ProjectIdentity?) {
        projectID = id
        reloadProjectScopedValues()
    }

    private func reloadProjectScopedValues() {
        let newShowsChangesOnly = defaults.bool(forKey: effectiveKey(Key.showsChangesOnly))
        if newShowsChangesOnly != showsChangesOnly { showsChangesOnly = newShowsChangesOnly }

        let newShowsIgnoredFiles = defaults.bool(forKey: effectiveKey(Key.showsIgnoredFiles))
        if newShowsIgnoredFiles != showsIgnoredFiles { showsIgnoredFiles = newShowsIgnoredFiles }

        let newTreeStyle =
            defaults.string(forKey: effectiveKey(Key.treeStyle)).flatMap(FileTreeStyle.init(rawValue:)) ?? .hierarchy
        if newTreeStyle != treeStyle { treeStyle = newTreeStyle }

        let newContextLines = defaults.object(forKey: effectiveKey(Key.contextLines)) as? Int ?? 3
        if newContextLines != contextLines { contextLines = newContextLines }

        let newDiagnosticsEnabled = defaults.bool(forKey: effectiveKey(Key.diagnosticsEnabled))
        if newDiagnosticsEnabled != diagnosticsEnabled { diagnosticsEnabled = newDiagnosticsEnabled }

        let newAnalyzedSides =
            defaults.string(forKey: effectiveKey(Key.analyzedSides)).flatMap(AnalyzedSides.init(rawValue:)) ?? .newer
        if newAnalyzedSides != analyzedSides { analyzedSides = newAnalyzedSides }

        let newDiffHeuristics =
            defaults.data(forKey: effectiveKey(Key.diffHeuristics))
            .flatMap { try? JSONDecoder().decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
        if newDiffHeuristics != diffHeuristics { diffHeuristics = newDiffHeuristics }

        let newToolLocations = Self.decodeToolLocations(defaults.data(forKey: effectiveKey(Key.toolLocations)))
        if newToolLocations != toolLocations { toolLocations = newToolLocations }

        let newLspServerLocations =
            defaults.data(forKey: effectiveKey(Key.lspServerLocations))
            .flatMap { try? JSONDecoder().decode([String: ToolLocation].self, from: $0) } ?? [
                "sourcekit-lsp": ToolLocation()
            ]
        if newLspServerLocations != lspServerLocations { lspServerLocations = newLspServerLocations }
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
