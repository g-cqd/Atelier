import AtelierDiagnostics
import DiffCore
import DiffRendering
package import Foundation
import Observation

/// Which configuration the Settings window edits (book SET-03, decision D11): the defaults every project starts from,
/// or one project's own settings on top of them. The tabs bind to ``edited``; the known projects and what each
/// overrides come from here too, so the views stay free of logic.
@Observable
@MainActor
package final class SettingsScope {
    /// What the Settings window edits.
    package enum Selection: Hashable, Sendable {
        /// The values every project uses unless it overrides them.
        case defaults
        /// One project's own values.
        case project(ProjectIdentity)
    }

    /// A known project and what it overrides, for the Projects tab.
    package struct Entry: Identifiable, Equatable {
        package let project: ProjectIdentity
        package let overrides: [SettingOverride]

        package var id: String { project.key }
    }

    package private(set) var selection = Selection.defaults
    /// The settings the tabs edit: the app's own instance for the defaults, an instance on the project otherwise.
    package private(set) var edited: ViewerSettings
    /// Every known project with what it overrides, kept current as windows adopt projects and overrides change.
    package private(set) var entries: [Entry] = []

    /// The app's instance, which never adopts a project; the tabs edit it for the defaults.
    package let appSettings: ViewerSettings
    /// `nonisolated(unsafe)`: written once at the end of `init` and read once in the nonisolated `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    package init(appSettings: ViewerSettings) {
        self.appSettings = appSettings
        edited = appSettings
        refresh()
        observers = [ViewerSettings.projectsChangedNotification, ViewerSettings.settingChangedNotification]
            .map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Whether the tabs edit one project's values rather than the defaults.
    package var isEditingProject: Bool {
        if case .project = selection { true } else { false }
    }

    /// Makes the tabs edit `selection`: a project is edited through an instance of its own, so the app-wide one, which
    /// applies the appearance, never adopts it.
    package func select(_ selection: Selection) {
        guard selection != self.selection else { return }
        self.selection = selection
        switch selection {
            case .defaults:
                edited = appSettings
            case .project(let project):
                let settings = ViewerSettings(defaults: appSettings.defaults)
                settings.adoptProject(project)
                edited = settings
        }
    }

    /// Drops `project`'s own value of the setting stored under `key`, which then follows the defaults again.
    package func resetOverride(_ key: String, of project: ProjectIdentity) {
        appSettings.clearOverride(key, projectKey: project.key)
    }

    /// Drops every value `project` overrides; the project stays in the list.
    package func resetOverrides(of project: ProjectIdentity) {
        appSettings.clearAllOverrides(projectKey: project.key)
    }

    /// Drops every value `project` overrides and removes it from the list until a window opens it again; the tabs go
    /// back to the defaults if they were editing it.
    package func remove(_ project: ProjectIdentity) {
        appSettings.forgetProject(projectKey: project.key)
        if selection == .project(project) { select(.defaults) }
    }

    /// Re-reads the known projects and their overrides, which live in user defaults that observation cannot see.
    package func refresh() {
        let updated = appSettings.knownProjects.map { project in
            Entry(project: project, overrides: SettingOverride.list(for: project, over: appSettings))
        }
        if updated != entries { entries = updated }
    }
}

/// One setting a project overrides, as the Projects tab lists it.
package struct SettingOverride: Identifiable, Equatable, Sendable {
    /// The setting's defaults key, which ``SettingsScope/resetOverride(_:of:)`` takes.
    package let key: String
    package let label: String
    /// The project's own value.
    package let value: String
    /// The value the project would have without the override.
    package let defaultValue: String

    package var id: String { key }
}

extension SettingOverride {
    /// Every setting `project` overrides, in the order the Settings tabs show them, read through a scratch instance so
    /// each value decodes exactly as a window on the project would read it; `base` supplies the values it overrides.
    @MainActor
    static func list(for project: ProjectIdentity, over base: ViewerSettings) -> [SettingOverride] {
        let keys = base.overriddenKeys(projectKey: project.key)
        guard !keys.isEmpty else { return [] }
        let reader = ViewerSettings(defaults: base.defaults)
        reader.projectID = project
        reader.applyingStoredValues { for key in keys { reader.reload(key: key) } }
        return keys.map { key in
            SettingOverride(
                key: key, label: Self.label(of: key), value: Self.value(of: key, in: reader),
                defaultValue: Self.value(of: key, in: base))
        }
    }

    private static func label(of key: String) -> String {
        typealias Key = ViewerSettings.Key
        return switch key {
            case Key.mode: SettingLabel.diffLayout
            case Key.wrapsLines: SettingLabel.wrapsLines
            case Key.wrapColumn: SettingLabel.wrapColumn
            case Key.showsMinimap: SettingLabel.showsMinimap
            case Key.isolatesChanges: SettingLabel.isolatesChanges
            case Key.contextLines: SettingLabel.contextLines
            case Key.granularity: SettingLabel.granularity
            case Key.diffHeuristics: SettingLabel.matching
            case Key.bouncesAtEdges: SettingLabel.bouncesAtEdges
            case Key.scrollsPastEnd: SettingLabel.scrollsPastEnd
            case Key.scrollsToFirstChange: SettingLabel.scrollsToFirstChange
            case Key.showsHoverDocumentation: SettingLabel.showsHoverDocumentation
            case Key.hoverPanelMaterial: SettingLabel.hoverPanelMaterial
            case Key.diagnosticsEnabled: SettingLabel.diagnosticsEnabled
            case Key.analyzedSides: SettingLabel.analyzedSides
            case Key.autoRefresh: SettingLabel.autoRefresh
            case Key.toolLocations: SettingLabel.tools
            case Key.lspServerLocations: SettingLabel.languageServers
            case Key.showsChangesOnly: SettingLabel.showsChangesOnly
            case Key.showsIgnoredFiles: SettingLabel.showsIgnoredFiles
            case Key.treeStyle: SettingLabel.treeStyle
            case Key.groupsByCommit: SettingLabel.groupsByCommit
            default: key
        }
    }

    @MainActor
    private static func value(of key: String, in settings: ViewerSettings) -> String {
        typealias Key = ViewerSettings.Key
        return switch key {
            case Key.mode: settings.mode.displayName
            case Key.wrapsLines: onOff(settings.wrapsLines)
            case Key.wrapColumn: settings.wrapColumn > 0 ? "\(settings.wrapColumn) characters" : "Pane width"
            case Key.showsMinimap: onOff(settings.showsMinimap)
            case Key.isolatesChanges: onOff(settings.isolatesChanges)
            case Key.contextLines: "\(settings.contextLines)"
            case Key.granularity: settings.granularity.displayName
            case Key.diffHeuristics: describe(settings.diffHeuristics)
            case Key.bouncesAtEdges: onOff(settings.bouncesAtEdges)
            case Key.scrollsPastEnd: onOff(settings.scrollsPastEnd)
            case Key.scrollsToFirstChange: onOff(settings.scrollsToFirstChange)
            case Key.showsHoverDocumentation: onOff(settings.showsHoverDocumentation)
            case Key.hoverPanelMaterial: settings.hoverPanelMaterial.displayName
            case Key.diagnosticsEnabled: onOff(settings.diagnosticsEnabled)
            case Key.analyzedSides: settings.analyzedSides.displayName
            case Key.autoRefresh: onOff(settings.autoRefresh)
            case Key.toolLocations:
                describe(settings.toolLocations.map { (name: $0.key.displayName, location: $0.value) })
            case Key.lspServerLocations:
                describe(settings.lspServerLocations.map { (name: $0.key, location: $0.value) })
            case Key.showsChangesOnly: onOff(settings.showsChangesOnly)
            case Key.showsIgnoredFiles: onOff(settings.showsIgnoredFiles)
            case Key.treeStyle: settings.treeStyle.displayName
            case Key.groupsByCommit: onOff(settings.groupsByCommit)
            default: ""
        }
    }

    private static func onOff(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    /// The whitespace mode, then every heuristic that differs from its default.
    private static func describe(_ heuristics: DiffHeuristics) -> String {
        let defaults = DiffHeuristics()
        let toggles: [(String, KeyPath<DiffHeuristics, Bool>)] = [
            (SettingLabel.anchorsRareLines, \.anchorsRareLines),
            (SettingLabel.slidesToIndentation, \.slidesToIndentation),
            (SettingLabel.pairsSimilarLines, \.pairsSimilarLines),
            (SettingLabel.cleansUpEmphasis, \.cleansUpEmphasis),
            (SettingLabel.detectsMovedBlocks, \.detectsMovedBlocks)
        ]
        let changed = toggles.filter { heuristics[keyPath: $0.1] != defaults[keyPath: $0.1] }
            .map { "\($0.0) \(onOff(heuristics[keyPath: $0.1]).lowercased())" }
        return ([heuristics.whitespace.displayName] + changed).joined(separator: "; ")
    }

    /// Every tool or server that is off or pinned to a path, by name; "Automatic" when none is.
    private static func describe(_ locations: [(name: String, location: ToolLocation)]) -> String {
        let parts = locations.sorted { $0.name < $1.name }
            .compactMap { name, location -> String? in
                if !location.isEnabled { return "\(name) off" }
                return location.customPath.map { "\(name) at \($0)" }
            }
        return parts.isEmpty ? "Automatic" : parts.joined(separator: "; ")
    }
}
