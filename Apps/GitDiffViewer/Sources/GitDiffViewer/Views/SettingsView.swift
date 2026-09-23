import AtelierDiagnostics
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The settings window: one tab per concern, each a grouped form that scrolls, in a window of a fixed size so it
/// never outgrows the screen. It reopens on the last-viewed tab, ``ViewerSettings/settingsPane``.
struct SettingsView: View {
    @Bindable var settings: ViewerSettings
    let runner: any ProcessRunner
    let discovery: ToolDiscovery

    var body: some View {
        TabView(selection: $settings.settingsPane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) {
                GeneralSettings(settings: settings)
            }
            Tab("Diff", systemImage: "text.line.first.and.arrowtriangle.forward", value: SettingsPane.diff) {
                DiffSettings(settings: settings)
            }
            Tab("Appearance", systemImage: "paintpalette", value: SettingsPane.appearance) {
                AppearanceSettings(settings: settings, runner: runner)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver", value: SettingsPane.tools) {
                ToolsSettings(settings: settings, discovery: discovery)
            }
        }
        .frame(width: 560, height: 520)
    }
}

/// General: how the window and its files are arranged, independent of any one diff.
private struct GeneralSettings: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("File Explorers") {
                    Picker(SettingLabel.explorerPlacement, selection: $settings.explorerPlacement) {
                        Text("Two explorers above the diff").tag(ExplorerPlacement.top)
                        Text("Two explorers in a sidebar").tag(ExplorerPlacement.sidebar)
                        Text("One merged tree in a sidebar").tag(ExplorerPlacement.unifiedSidebar)
                    }
                    Picker(SettingLabel.treeStyle, selection: $settings.treeStyle) {
                        Text("Tree").tag(FileTreeStyle.hierarchy)
                        Text("Tree with compact folders").tag(FileTreeStyle.compact)
                        Text("Flat list of paths").tag(FileTreeStyle.flat)
                    }
                    Toggle(SettingLabel.showsChangesOnly, isOn: $settings.showsChangesOnly)
                    Toggle(SettingLabel.showsIgnoredFiles, isOn: $settings.showsIgnoredFiles)
                    Text(
                        "Folders take the status of their contents: added or removed when all files are, changed otherwise."
                    )
                    .settingsCaption()
                }
                Section("Window") {
                    Toggle(SettingLabel.syncScrolling, isOn: $settings.syncsScrolling)
                    Toggle(SettingLabel.showsMinimap, isOn: $settings.showsMinimap)
                    Toggle(SettingLabel.showsStatusBar, isOn: $settings.showsStatusBar)
                    Toggle(SettingLabel.autoRefresh, isOn: $settings.autoRefresh)
                    Text(
                        "Watches the working tree and the repository's HEAD and refs, and reloads this window on its own."
                    )
                    .settingsCaption()
                }
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, category: .general)
        }
        .navigationTitle("General")
    }
}

/// Diff: what's compared and how it's matched: isolation and context, then granularity, whitespace and the
/// advanced matching heuristics.
private struct DiffSettings: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        VStack(spacing: 0) {
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
                        Text("Characters").tag(IntralineGranularity.character)
                        Text("Words").tag(IntralineGranularity.word)
                        Text("Syntax").tag(IntralineGranularity.syntax)
                    }
                    Text(
                        "Syntax uses swift-syntax tokens for Swift files and a code-aware lexer for the other languages."
                    )
                    .settingsCaption()
                    Picker(SettingLabel.whitespace, selection: $settings.diffHeuristics.whitespace) {
                        Text("Exactly").tag(WhitespaceMode.exact)
                        Text("Ignoring trailing whitespace").tag(WhitespaceMode.ignoreTrailing)
                        Text("Ignoring leading and trailing whitespace").tag(WhitespaceMode.ignoreLeadingAndTrailing)
                        Text("Ignoring all whitespace").tag(WhitespaceMode.ignoreAll)
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
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, category: .diff)
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
    let runner: any ProcessRunner
    @State private var themes: [XcodeThemeLibrary.Entry] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Colors") {
                    Picker(SettingLabel.appearanceScheme, selection: $settings.appearanceScheme) {
                        Text("System").tag(AppearanceScheme.system)
                        Text("Light").tag(AppearanceScheme.light)
                        Text("Dark").tag(AppearanceScheme.dark)
                    }
                    .pickerStyle(.segmented)
                    Text(
                        "Match the system, or pin the window chrome light or dark — useful when the diff theme is "
                            + "the other way."
                    )
                    .settingsCaption()
                    Toggle(SettingLabel.matchesThemeAppearance, isOn: $settings.matchesThemeAppearance)
                        .disabled(settings.appearanceScheme != .system)
                    Text("Switch the window light or dark to match the selected color scheme.")
                        .settingsCaption()
                    Picker("Color scheme", selection: $settings.themePath) {
                        Text("System").tag(String?.none)
                        ForEach(themes) { theme in
                            Text(theme.name).tag(String?.some(theme.url.path(percentEncoded: false)))
                        }
                    }
                    Text(
                        "Xcode themes from ~/Library/Developer/Xcode/UserData/FontAndColorThemes and the selected Xcode."
                    )
                    .settingsCaption()
                    Picker("Line height", selection: $settings.lineHeightMultiple) {
                        Text("Theme").tag(0.0)
                        ForEach([0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0], id: \.self) { multiple in
                            Text(multiple.formatted(.number.precision(.fractionLength(0 ... 2))) + "×").tag(multiple)
                        }
                    }
                    Text("Theme follows the selected Xcode theme's line spacing, or 1× with the system colors.")
                        .settingsCaption()
                }
                Section("Badges") {
                    Picker(SettingLabel.badgeScheme, selection: $settings.badgeScheme) {
                        Text("Classic").tag(BadgeScheme.classic)
                        Text("Xcode").tag(BadgeScheme.xcode)
                    }
                    .pickerStyle(.segmented)
                    Text("Xcode's scheme reads a modification and a rename both as blue.")
                        .settingsCaption()
                }
                Section("Layout") {
                    Picker("Diff layout", selection: $settings.mode) {
                        Text("Inline").tag(ViewMode.inline)
                        Text("Side by side").tag(ViewMode.split)
                        Text("Stacked").tag(ViewMode.stacked)
                    }
                    Text("The card list shows Stacked side by side.")
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
            SettingsRestoreDefaultsFooter(settings: settings, category: .appearance)
        }
        .navigationTitle("Appearance")
    }

    private var wrapsAtColumn: Binding<Bool> {
        Binding(
            get: { settings.wrapColumn > 0 },
            set: { settings.wrapColumn = $0 ? 120 : 0 }
        )
    }
}

/// A tab's footer: how many settings differ from their coded default, a button that resets the tab, and, for a tab
/// with project-scoped settings, how many projects override them, with a "Review…" button to clear those.
struct SettingsRestoreDefaultsFooter: View {
    @Bindable var settings: ViewerSettings
    let category: SettingsCategory
    @State private var isReviewingOverrides = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                let count = settings.settingsDiffCount(category)
                if count > 0 {
                    Text("\(count) setting\(count == 1 ? "" : "s") differ\(count == 1 ? "s" : "") from defaults")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore Defaults") { settings.restoreDefaults(category) }
                    .disabled(count == 0)
            }
            let overriddenProjects = settings.projectsWithOverrides(in: category)
            if !overriddenProjects.isEmpty {
                HStack {
                    Text(
                        "Overridden in \(overriddenProjects.count) project\(overriddenProjects.count == 1 ? "" : "s")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Review…") { isReviewingOverrides = true }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .sheet(isPresented: $isReviewingOverrides) {
            ProjectOverridesReview(settings: settings, category: category)
        }
    }
}

/// Lists every project overriding one of `category`'s settings, each with a "Clear" button, plus "Clear All". The
/// registry lives in user defaults, which observation cannot see, so `projects` reloads after every clear.
private struct ProjectOverridesReview: View {
    let settings: ViewerSettings
    let category: SettingsCategory
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [(key: String, displayPath: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Project Overrides").font(.headline).padding([.horizontal, .top], 16)
            List(projects, id: \.key) { project in
                HStack {
                    Text(project.displayPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Clear") { clear(project.key) }
                }
            }
            .frame(minHeight: 120)
            HStack {
                Button("Clear All") {
                    for project in projects { settings.clearOverrides(projectKey: project.key, category: category) }
                    refresh()
                }
                .disabled(projects.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420, height: 280)
        .onAppear(perform: refresh)
    }

    private func clear(_ projectKey: String) {
        settings.clearOverrides(projectKey: projectKey, category: category)
        refresh()
    }

    private func refresh() {
        projects = settings.projectsWithOverrides(in: category)
    }
}

extension Text {
    func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
