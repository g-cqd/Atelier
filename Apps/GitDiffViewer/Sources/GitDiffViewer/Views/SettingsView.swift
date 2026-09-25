import AtelierDiagnostics
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The settings window: one tab per concern, each a grouped form that scrolls, in a window of a fixed size so it
/// never outgrows the screen. It reopens on the last-viewed tab, ``ViewerSettings/settingsPane``. A selector at the
/// top of each tab chooses what the tab edits: the defaults, or one project's own settings (``SettingsScope``).
struct SettingsView: View {
    @Bindable var settings: ViewerSettings
    let runner: any ProcessRunner
    let discovery: ToolDiscovery
    @State private var scope: SettingsScope

    init(settings: ViewerSettings, runner: any ProcessRunner, discovery: ToolDiscovery) {
        self.settings = settings
        self.runner = runner
        self.discovery = discovery
        _scope = State(initialValue: SettingsScope(appSettings: settings))
    }

    var body: some View {
        TabView(selection: $settings.settingsPane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                GeneralSettings(settings: scope.edited, scope: scope)
            }
            Tab("Diff", systemImage: "text.line.first.and.arrowtriangle.forward", value: SettingsPane.diff) {
                DiffSettings(settings: scope.edited, scope: scope)
            }
            Tab("Appearance", systemImage: "paintpalette", value: SettingsPane.appearance) {
                AppearanceSettings(settings: scope.edited, scope: scope, runner: runner)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: SettingsPane.tools) {
                ToolsSettings(settings: scope.edited, scope: scope, discovery: discovery)
            }
            Tab("Projects", systemImage: "folder.badge.gearshape", value: SettingsPane.projects) {
                ProjectsSettings(scope: scope)
            }
        }
        .frame(width: 560, height: 560)
    }
}

/// General: how the window and its files are arranged, independent of any one diff.
private struct GeneralSettings: View {
    @Bindable var settings: ViewerSettings
    let scope: SettingsScope

    var body: some View {
        VStack(spacing: 0) {
            SettingsScopeBar(scope: scope)
            Form {
                Section("File Explorers") {
                    Picker(SettingLabel.explorerPlacement, selection: $settings.explorerPlacement) {
                        Text("Two explorers above the diff").tag(ExplorerPlacement.top)
                        Text("Two explorers in a sidebar").tag(ExplorerPlacement.sidebar)
                        Text("One merged tree in a sidebar").tag(ExplorerPlacement.unifiedSidebar)
                    }
                    .appWide(\.explorerPlacement, in: scope)
                    Picker(SettingLabel.treeStyle, selection: $settings.treeStyle) {
                        ForEach(FileTreeStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle(SettingLabel.groupsByCommit, isOn: $settings.groupsByCommit)
                    Text(
                        """
                        Lists the files each commit changed under a section of its own. Applies to the flat list in \
                        the merged sidebar, when the left side is an ancestor of the right in one repository.
                        """
                    )
                    .settingsCaption()
                    Toggle(SettingLabel.showsChangesOnly, isOn: $settings.showsChangesOnly)
                    Toggle(SettingLabel.showsIgnoredFiles, isOn: $settings.showsIgnoredFiles)
                    Text(
                        "Folders take the status of their contents: added or removed when all files are, changed otherwise."
                    )
                    .settingsCaption()
                }
                Section("Window") {
                    Toggle(SettingLabel.syncScrolling, isOn: $settings.syncsScrolling)
                        .appWide(\.syncsScrolling, in: scope)
                    Toggle(SettingLabel.showsMinimap, isOn: $settings.showsMinimap)
                    Toggle(SettingLabel.showsStatusBar, isOn: $settings.showsStatusBar)
                        .appWide(\.showsStatusBar, in: scope)
                    Toggle(SettingLabel.autoRefresh, isOn: $settings.autoRefresh)
                    Text(
                        "Watches the working tree and the repository's HEAD and refs, and reloads this window on its own."
                    )
                    .settingsCaption()
                }
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, scope: scope, category: .general)
        }
        .navigationTitle("General")
    }
}

/// Diff: what's compared and how it's matched: isolation and context, then granularity, whitespace and the
/// advanced matching heuristics; then how the code panes scroll.
private struct DiffSettings: View {
    @Bindable var settings: ViewerSettings
    let scope: SettingsScope

    var body: some View {
        VStack(spacing: 0) {
            SettingsScopeBar(scope: scope)
            Form {
                Section("Changes") {
                    Toggle(SettingLabel.isolatesChanges, isOn: $settings.isolatesChanges)
                    Stepper(
                        "\(SettingLabel.contextLines): \(settings.contextLines)", value: $settings.contextLines,
                        in: 0 ... 20
                    )
                    .disabled(!settings.isolatesChanges)
                    Text("Isolating changes shows only the changed regions, with the context lines around each.")
                        .settingsCaption()
                }
                Section("Matching") {
                    Picker(SettingLabel.granularity, selection: $settings.granularity) {
                        ForEach(IntralineGranularity.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(
                        "Syntax uses swift-syntax tokens for Swift files and a code-aware lexer for the other languages."
                    )
                    .settingsCaption()
                    Picker(SettingLabel.whitespace, selection: $settings.diffHeuristics.whitespace) {
                        ForEach(WhitespaceMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    DisclosureGroup(SettingLabel.advancedMatching) {
                        VStack(alignment: .leading, spacing: 8) {
                            heuristicToggle(
                                SettingLabel.anchorsRareLines, isOn: $settings.diffHeuristics.anchorsRareLines,
                                caption: "Matches rare lines first (git's histogram algorithm) before filling in "
                                    + "the rest, instead of the plain shortest edit script. Helps repetitive files "
                                    + "where the shortest script picks a confusing match."
                            )
                            heuristicToggle(
                                SettingLabel.slidesToIndentation, isOn: $settings.diffHeuristics.slidesToIndentation,
                                caption: "Slides a change's boundaries to line up with indentation, the way git's "
                                    + "own indent heuristic does, so a change starts and ends on a natural line."
                            )
                            heuristicToggle(
                                SettingLabel.pairsSimilarLines, isOn: $settings.diffHeuristics.pairsSimilarLines,
                                caption: "Pairs changed lines by how similar their content is rather than by "
                                    + "position, so intraline emphasis lands on the right counterpart."
                            )
                            heuristicToggle(
                                SettingLabel.cleansUpEmphasis, isOn: $settings.diffHeuristics.cleansUpEmphasis,
                                caption: "Merges scattered intraline edits and aligns them to token boundaries, "
                                    + "the way diff-match-patch cleans up a noisy character-level diff."
                            )
                            heuristicToggle(
                                SettingLabel.detectsMovedBlocks, isOn: $settings.diffHeuristics.detectsMovedBlocks,
                                caption: "Marks blocks of lines that only moved, rather than showing them as a "
                                    + "removal on one side and an addition on the other."
                            )
                        }
                        .padding(.top, 4)
                    }
                }
                Section("Scrolling") {
                    Toggle(SettingLabel.bouncesAtEdges, isOn: $settings.bouncesAtEdges)
                    Text(
                        "The file's panes and the cards' panes rubber-band past their edges. The card list always does."
                    )
                    .settingsCaption()
                    Toggle(SettingLabel.scrollsPastEnd, isOn: $settings.scrollsPastEnd)
                    Text("A file scrolls on until its last line reaches the top, rather than stopping at the bottom.")
                        .settingsCaption()
                    Toggle(SettingLabel.scrollsToFirstChange, isOn: $settings.scrollsToFirstChange)
                    Text(
                        "Off, a file opens at its top. A tab you come back to keeps its place, and a file that fits shows whole."
                    )
                    .settingsCaption()
                }
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, scope: scope, category: .diff)
        }
        .navigationTitle("Diff")
    }

    @ViewBuilder
    private func heuristicToggle(_ title: String, isOn: Binding<Bool>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
            Text(caption).settingsCaption()
        }
    }
}

/// Appearance: colors and line height, badge colors, and the diff's layout and wrapping.
private struct AppearanceSettings: View {
    @Bindable var settings: ViewerSettings
    let scope: SettingsScope
    let runner: any ProcessRunner
    @State private var themes: [XcodeThemeLibrary.Entry] = []

    /// Whether the language named `name` takes its grammar's colour: on unless the setting lists it.
    private func grammarColorBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !settings.grammarColorOff.contains(name) },
            set: { isOn in
                if isOn {
                    settings.grammarColorOff.remove(name)
                } else {
                    settings.grammarColorOff.insert(name)
                }
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsScopeBar(scope: scope)
            Form {
                Section {
                    colors
                } header: {
                    Text("Colors")
                } footer: {
                    if scope.isEditingProject { Text("The same in every project.").settingsCaption() }
                }
                Section {
                    Toggle(SettingLabel.refinesSwiftColor, isOn: $settings.refinesSwiftColor)
                        .appWide(\.refinesSwiftColor, in: scope)
                    Text(
                        "Swift files show quick colors at once, then swift-syntax's, which reads the code as the compiler does."
                    )
                    .settingsCaption()
                    Toggle(SettingLabel.semanticColor, isOn: $settings.semanticColor)
                        .appWide(\.semanticColor, in: scope)
                        .disabled(!settings.refinesSwiftColor)
                    Text(
                        "Names in files on disk then take sourcekit-lsp's colors, in repositories you trust; keywords, "
                            + "comments and literals keep swift-syntax's."
                    )
                    .settingsCaption()
                } header: {
                    Text("Syntax Color")
                }
                Section {
                    ForEach(ColorTierGate.settingRows) { row in
                        Toggle(row.title, isOn: grammarColorBinding(row.id))
                            .appWide(\.grammarColorOff, in: scope)
                    }
                    Text(
                        "Files in these languages show quick colors at once, then their grammar's. A grammar whose "
                            + "compiled tables are larger than 20 MB, such as TypeScript's or C++'s, keeps the quick "
                            + "colors, and so does a file its grammar cannot read within a quarter of a second."
                    )
                    .settingsCaption()
                } header: {
                    Text(SettingLabel.grammarColor)
                }
                Section {
                    Picker(SettingLabel.badgeScheme, selection: $settings.badgeScheme) {
                        Text("Classic").tag(BadgeScheme.classic)
                        Text("Xcode").tag(BadgeScheme.xcode)
                    }
                    .pickerStyle(.segmented)
                    .appWide(\.badgeScheme, in: scope)
                    Text("Xcode's scheme reads a modification and a rename both as blue.")
                        .settingsCaption()
                    Picker(SettingLabel.diffColors, selection: $settings.diffColors) {
                        Text("Red and green").tag(DiffColors.standard)
                        Text("Xcode").tag(DiffColors.xcode)
                    }
                    .pickerStyle(.segmented)
                    .appWide(\.diffColors, in: scope)
                    Text(
                        "Xcode's colors show a removed line gray and an added one blue, with a blue bar beside each "
                            + "change in the gutter."
                    )
                    .settingsCaption()
                } header: {
                    Text("Change Colors")
                }
                Section("Layout") {
                    Picker(SettingLabel.diffLayout, selection: $settings.mode) {
                        ForEach(ViewMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text("The card list shows Stacked side by side.")
                        .settingsCaption()
                    Toggle(SettingLabel.compactsInlineView, isOn: $settings.compactsInlineView)
                        .appWide(\.compactsInlineView, in: scope)
                    Text(
                        "Inline, shows the new file alone, with a marker in the gutter at each change. Click a marker, "
                            + "or press ⌥⌘↩, to show the change in place."
                    )
                    .settingsCaption()
                    Toggle(SettingLabel.wrapsLines, isOn: $settings.wrapsLines)
                    Toggle("Wrap at a fixed column", isOn: wrapsAtColumn)
                        .disabled(!settings.wrapsLines)
                    if settings.wrapsLines, settings.wrapColumn > 0 {
                        Stepper("Column: \(settings.wrapColumn)", value: $settings.wrapColumn, in: 40 ... 400, step: 10)
                    }
                    Text("In the side-by-side layout, paired rows keep the same height on both sides when lines wrap.")
                        .settingsCaption()
                }
            }
            .formStyle(.grouped)
            .task { themes = await XcodeThemeLibrary.entries(runner: runner) }
            SettingsRestoreDefaultsFooter(settings: settings, scope: scope, category: .appearance)
        }
        .navigationTitle("Appearance")
    }

    @ViewBuilder private var colors: some View {
        Picker(SettingLabel.appearanceScheme, selection: $settings.appearanceScheme) {
            Text("System").tag(AppearanceScheme.system)
            Text("Light").tag(AppearanceScheme.light)
            Text("Dark").tag(AppearanceScheme.dark)
        }
        .pickerStyle(.segmented)
        .appWide(\.appearanceScheme, in: scope)
        Text(
            "Match the system, or pin the window chrome light or dark — useful when the diff theme is the other way."
        )
        .settingsCaption()
        Toggle(SettingLabel.matchesThemeAppearance, isOn: $settings.matchesThemeAppearance)
            .disabled(settings.appearanceScheme != .system)
            .appWide(\.matchesThemeAppearance, in: scope)
        Text("Switch the window light or dark to match the selected color scheme.")
            .settingsCaption()
        Picker("Color scheme", selection: $settings.themePath) {
            Text("System").tag(String?.none)
            ForEach(themes) { theme in
                Text(theme.name).tag(String?.some(theme.url.path(percentEncoded: false)))
            }
        }
        .appWide(\.themePath, in: scope)
        Text("Xcode themes from ~/Library/Developer/Xcode/UserData/FontAndColorThemes and the selected Xcode.")
            .settingsCaption()
        Picker("Line height", selection: $settings.lineHeightMultiple) {
            Text("Theme").tag(0.0)
            ForEach([0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0], id: \.self) { multiple in
                Text(multiple.formatted(.number.precision(.fractionLength(0 ... 2))) + "×").tag(multiple)
            }
        }
        .appWide(\.lineHeightMultiple, in: scope)
        Text("Theme follows the selected Xcode theme's line spacing, or 1× with the system colors.")
            .settingsCaption()
    }

    private var wrapsAtColumn: Binding<Bool> {
        Binding(
            get: { settings.wrapColumn > 0 },
            set: { settings.wrapColumn = $0 ? 120 : 0 }
        )
    }
}

/// The selector at the top of every tab that chooses what the tab edits: the defaults, or one known project's own
/// settings, with a line saying which values the edits reach.
struct SettingsScopeBar: View {
    let scope: SettingsScope

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(SettingLabel.settingsScope, selection: selection) {
                Text("Default").tag(SettingsScope.Selection.defaults)
                if !scope.entries.isEmpty { Divider() }
                ForEach(scope.entries) { entry in
                    Text(entry.project.name).tag(SettingsScope.Selection.project(entry.project))
                        .help(entry.project.displayPath)
                }
            }
            Text(caption).settingsCaption()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var selection: Binding<SettingsScope.Selection> {
        Binding(get: { scope.selection }, set: { scope.select($0) })
    }

    private var caption: String {
        switch scope.selection {
            case .defaults:
                "Every project uses these values unless it has its own."
            case .project(let project):
                "Changes apply to \(project.name) only. Greyed-out settings are the same in every project."
        }
    }
}

extension View {
    /// Greys out a control whose setting is the same in every project while the Settings window edits a project.
    func appWide(_ property: PartialKeyPath<ViewerSettings>, in scope: SettingsScope) -> some View {
        disabled(scope.isEditingProject && !ViewerSettings.isProjectScoped(property))
    }
}

/// A tab's footer. For the defaults: how many settings differ from their coded default, a button that resets the tab,
/// and how many projects override the tab's settings, with a button to the Projects tab. For a project: how many of
/// the tab's settings it overrides, and a button that drops those overrides.
struct SettingsRestoreDefaultsFooter: View {
    @Bindable var settings: ViewerSettings
    let scope: SettingsScope
    let category: SettingsCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let count =
                    scope.isEditingProject ? settings.overrideCount(category) : settings.settingsDiffCount(category)
                if count > 0 {
                    Text(countText(count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore Defaults") { settings.restoreDefaults(category) }
                    .disabled(count == 0)
            }
            if !scope.isEditingProject {
                let overriddenProjects = settings.projectsWithOverrides(in: category)
                if !overriddenProjects.isEmpty {
                    HStack {
                        let count = overriddenProjects.count
                        Text("Overridden in \(count) project\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Review…") { scope.appSettings.settingsPane = .projects }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func countText(_ count: Int) -> String {
        guard case .project(let project) = scope.selection else {
            return "\(count) setting\(count == 1 ? "" : "s") differ\(count == 1 ? "s" : "") from defaults"
        }
        return "\(count) setting\(count == 1 ? "" : "s") overridden in \(project.name)"
    }
}

extension Text {
    func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
