package import AtelierDiagnostics
import DiffCore
import DiffRendering
import Foundation

/// Restoring defaults and counting deviations, per Settings tab.
extension ViewerSettings {
    /// Resets `category`'s settings through the same setters as a user edit. With no project adopted, every setting
    /// returns to its coded default. Once a project is adopted, only its overrides go, each scoped setting falling
    /// back to the app-wide value, and the app-wide settings stay as they are: restoring a project's tab must not
    /// reset what every other project shares.
    package func restoreDefaults(_ category: SettingsCategory) {
        applyWithoutRecreatingScopedOverrides {
            switch category {
                case .general: restoreGeneral()
                case .diff: restoreDiff()
                case .appearance: restoreAppearance()
                case .tools: restoreTools()
            }
        }
    }

    private func restoreGeneral() {
        restoreAppWide {
            explorerPlacement = .top
            syncsScrolling = true
            showsStatusBar = true
        }
        treeStyle = restoredValue(Key.treeStyle, appDefault: FileTreeStyle.hierarchy) {
            Self.storedTreeStyle(defaults, key: Key.treeStyle)
        }
        showsChangesOnly = restoredValue(Key.showsChangesOnly, appDefault: false) {
            defaults.bool(forKey: Key.showsChangesOnly)
        }
        showsIgnoredFiles = restoredValue(Key.showsIgnoredFiles, appDefault: false) {
            defaults.bool(forKey: Key.showsIgnoredFiles)
        }
        groupsByCommit = restoredValue(Key.groupsByCommit, appDefault: false) {
            defaults.bool(forKey: Key.groupsByCommit)
        }
        showsMinimap = restoredValue(Key.showsMinimap, appDefault: true) {
            defaults.object(forKey: Key.showsMinimap) as? Bool ?? true
        }
        autoRefresh = restoredValue(Key.autoRefresh, appDefault: true) {
            defaults.object(forKey: Key.autoRefresh) as? Bool ?? true
        }
    }

    private func restoreDiff() {
        isolatesChanges = restoredValue(Key.isolatesChanges, appDefault: false) {
            defaults.bool(forKey: Key.isolatesChanges)
        }
        contextLines = restoredValue(Key.contextLines, appDefault: 3) {
            defaults.object(forKey: Key.contextLines) as? Int ?? 3
        }
        granularity = restoredValue(Key.granularity, appDefault: IntralineGranularity.word) {
            defaults.string(forKey: Key.granularity).flatMap(IntralineGranularity.init(rawValue:)) ?? .word
        }
        diffHeuristics = restoredValue(Key.diffHeuristics, appDefault: DiffHeuristics()) {
            defaults.data(forKey: Key.diffHeuristics)
                .flatMap { try? DefaultsJSON.decode(DiffHeuristics.self, from: $0) } ?? DiffHeuristics()
        }
        bouncesAtEdges = restoredValue(Key.bouncesAtEdges, appDefault: false) {
            defaults.bool(forKey: Key.bouncesAtEdges)
        }
        scrollsPastEnd = restoredValue(Key.scrollsPastEnd, appDefault: false) {
            defaults.bool(forKey: Key.scrollsPastEnd)
        }
        scrollsToFirstChange = restoredValue(Key.scrollsToFirstChange, appDefault: true) {
            defaults.object(forKey: Key.scrollsToFirstChange) as? Bool ?? true
        }
    }

    private func restoreAppearance() {
        restoreAppWide {
            themePath = nil
            lineHeightMultiple = 0
            appearanceScheme = .system
            badgeScheme = .classic
            diffColors = .standard
            matchesThemeAppearance = false
            refinesSwiftColor = true
            semanticColor = true
            grammarColorOff = []
            compactsInlineView = false
        }
        mode = restoredValue(Key.mode, appDefault: ViewMode.split) {
            defaults.string(forKey: Key.mode).flatMap(ViewMode.init(rawValue:)) ?? .split
        }
        wrapsLines = restoredValue(Key.wrapsLines, appDefault: true) {
            defaults.object(forKey: Key.wrapsLines) as? Bool ?? true
        }
        wrapColumn = restoredValue(Key.wrapColumn, appDefault: 0) { defaults.integer(forKey: Key.wrapColumn) }
    }

    private func restoreTools() {
        diagnosticsEnabled = restoredValue(Key.diagnosticsEnabled, appDefault: false) {
            defaults.bool(forKey: Key.diagnosticsEnabled)
        }
        showsHoverDocumentation = restoredValue(Key.showsHoverDocumentation, appDefault: true) {
            defaults.object(forKey: Key.showsHoverDocumentation) as? Bool ?? true
        }
        hoverPanelMaterial = restoredValue(Key.hoverPanelMaterial, appDefault: HoverPanelMaterial.liquidGlass) {
            defaults.string(forKey: Key.hoverPanelMaterial).flatMap(HoverPanelMaterial.init(rawValue:)) ?? .liquidGlass
        }
        analyzedSides = restoredValue(Key.analyzedSides, appDefault: AnalyzedSides.rightOnly) {
            defaults.string(forKey: Key.analyzedSides).flatMap(AnalyzedSides.init(storedValue:)) ?? .rightOnly
        }
        toolLocations = restoredValue(Key.toolLocations, appDefault: Self.defaultToolLocations) {
            Self.decodeToolLocations(defaults.data(forKey: Key.toolLocations))
        }
        lspServerLocations = restoredValue(Key.lspServerLocations, appDefault: Self.defaultLSPServerLocations) {
            defaults.data(forKey: Key.lspServerLocations)
                .flatMap { try? DefaultsJSON.decode([String: ToolLocation].self, from: $0) }
                ?? Self.defaultLSPServerLocations
        }
    }

    /// Runs `body`, which resets app-wide settings, only when no project is adopted.
    private func restoreAppWide(_ body: () -> Void) {
        guard projectID == nil else { return }
        body()
    }

    /// Clears `key`'s project override (if any) and returns what the property should become: the base value,
    /// decoded by `decodeBase`, when a project is adopted, or the coded app-wide default otherwise.
    private func restoredValue<Value>(_ key: String, appDefault: Value, decodeBase: () -> Value) -> Value {
        guard let projectID else { return appDefault }
        clearOverride(key, projectKey: projectID.key)
        return decodeBase()
    }

    /// Every tool these settings run, by its location: a tool ``toolLocations`` does not name counts at its default,
    /// enabled, as the Tools tab shows it.
    package var enabledToolLocations: [DiagnosticTool: ToolLocation] {
        Self.defaultToolLocations.merging(toolLocations) { _, set in set }.filter(\.value.isEnabled)
    }

    /// Every tool enabled, at no custom path.
    static var defaultToolLocations: [DiagnosticTool: ToolLocation] {
        Dictionary(uniqueKeysWithValues: DiagnosticTool.allCases.map { ($0, ToolLocation()) })
    }

    /// sourcekit-lsp enabled, at no custom path.
    static var defaultLSPServerLocations: [String: ToolLocation] { ["sourcekit-lsp": ToolLocation()] }

    /// The stored locations, with every tool the stored value does not name, such as one added since it was saved,
    /// at its default: enabled, as the Tools tab shows it, and so run. A tool missing from the dictionary used to
    /// read as enabled in Settings and never run.
    static func decodeToolLocations(_ data: Data?) -> [DiagnosticTool: ToolLocation] {
        let stored =
            data
            .flatMap { try? DefaultsJSON.decode([String: ToolLocation].self, from: $0) }
            .map { decoded in
                Dictionary(
                    uniqueKeysWithValues: decoded.compactMap { key, value in
                        DiagnosticTool(rawValue: key).map { ($0, value) }
                    })
            } ?? [:]
        return defaultToolLocations.merging(stored) { _, saved in saved }
    }

    /// How many settings in `category` differ from their coded default, for the tab footer's deviation indicator.
    package func settingsDiffCount(_ category: SettingsCategory) -> Int {
        switch category {
            case .general:
                return [
                    explorerPlacement != .top, treeStyle != .hierarchy, showsChangesOnly != false,
                    showsIgnoredFiles != false, groupsByCommit != false, syncsScrolling != true,
                    showsMinimap != true, showsStatusBar != true, autoRefresh != true
                ]
                .count { $0 }
            case .diff:
                return [
                    isolatesChanges != false, contextLines != 3, granularity != .word,
                    diffHeuristics != DiffHeuristics(), bouncesAtEdges != false, scrollsPastEnd != false,
                    scrollsToFirstChange != true
                ]
                .count { $0 }
            case .appearance:
                return [
                    themePath != nil, lineHeightMultiple != 0, mode != .split, wrapsLines != true, wrapColumn != 0,
                    appearanceScheme != .system, badgeScheme != .classic, matchesThemeAppearance != false,
                    refinesSwiftColor != true, semanticColor != true, !grammarColorOff.isEmpty,
                    compactsInlineView != false,
                    diffColors != .standard
                ]
                .count { $0 }
            case .tools:
                return [
                    diagnosticsEnabled != false, showsHoverDocumentation != true, hoverPanelMaterial != .liquidGlass,
                    analyzedSides != .rightOnly, toolLocations != Self.defaultToolLocations,
                    lspServerLocations != Self.defaultLSPServerLocations
                ]
                .count { $0 }
        }
    }

    /// How many of `category`'s settings the adopted project overrides; zero with no project adopted.
    package func overrideCount(_ category: SettingsCategory) -> Int {
        guard let projectID else { return 0 }
        return Self.scopedKeys(for: category).count { defaults.object(forKey: scopedKey($0, for: projectID)) != nil }
    }
}
