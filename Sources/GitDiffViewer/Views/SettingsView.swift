import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The settings window: one tab per concern, each a grouped form that scrolls, in a window of a fixed size so it
/// never outgrows the screen.
struct SettingsView: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: settings)
            }
            Tab("Diff", systemImage: "text.line.first.and.arrowtriangle.forward") {
                DiffSettings(settings: settings)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettings(settings: settings)
            }
        }
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Diff layout", selection: $settings.mode) {
                    Text("Inline").tag(ViewMode.inline)
                    Text("Side by side").tag(ViewMode.split)
                    Text("Stacked").tag(ViewMode.stacked)
                }
                Toggle("Isolate changes", isOn: $settings.isolatesChanges)
                Stepper("Context lines around changes: \(settings.contextLines)", value: $settings.contextLines, in: 0...20)
                    .disabled(!settings.isolatesChanges)
                Text("Isolating changes shows only the changed regions, with the context lines around each.")
                    .settingsCaption()
            }
            Section("File Explorers") {
                Picker("Placement", selection: $settings.explorerPlacement) {
                    Text("Two explorers above the diff").tag(ExplorerPlacement.top)
                    Text("Two explorers in a sidebar").tag(ExplorerPlacement.sidebar)
                    Text("One merged tree in a sidebar").tag(ExplorerPlacement.unifiedSidebar)
                }
                Picker("Arrange files as", selection: $settings.treeStyle) {
                    Text("Tree").tag(FileTreeStyle.hierarchy)
                    Text("Tree with compact folders").tag(FileTreeStyle.compact)
                    Text("Flat list of paths").tag(FileTreeStyle.flat)
                }
                Toggle("Show changed files only", isOn: $settings.showsChangesOnly)
                Toggle("Show the files git ignores in a section of their own", isOn: $settings.showsIgnoredFiles)
                Text("Folders take the status of their contents: added or removed when all files are, changed otherwise.")
                    .settingsCaption()
            }
            Section("Window") {
                Toggle("Keep split panes scrolled together", isOn: $settings.syncsScrolling)
                Toggle("Show minimap next to each pane", isOn: $settings.showsMinimap)
                Toggle("Show the status bar", isOn: $settings.showsStatusBar)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiffSettings: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        Form {
            Section("Changes") {
                Picker("Highlight changes by", selection: $settings.granularity) {
                    Text("Characters").tag(IntralineGranularity.character)
                    Text("Words").tag(IntralineGranularity.word)
                    Text("Syntax").tag(IntralineGranularity.syntax)
                }
                Text("Syntax uses swift-syntax tokens for Swift files and a code-aware lexer for the other languages.")
                    .settingsCaption()
            }
            Section("Algorithm") {
                Toggle("Anchor on rare lines first (histogram)", isOn: $settings.diffHeuristics.anchorsRareLines)
                Toggle("Slide change boundaries by indentation", isOn: $settings.diffHeuristics.slidesToIndentation)
                Toggle("Pair changed lines by similarity", isOn: $settings.diffHeuristics.pairsSimilarLines)
                Toggle("Clean up scattered emphasis", isOn: $settings.diffHeuristics.cleansUpEmphasis)
                Toggle("Mark blocks that only moved", isOn: $settings.diffHeuristics.detectsMovedBlocks)
            }
            Section("Whitespace") {
                Picker("Compare", selection: $settings.diffHeuristics.whitespace) {
                    Text("Exactly").tag(WhitespaceMode.exact)
                    Text("Ignoring trailing whitespace").tag(WhitespaceMode.ignoreTrailing)
                    Text("Ignoring leading and trailing whitespace").tag(WhitespaceMode.ignoreLeadingAndTrailing)
                    Text("Ignoring all whitespace").tag(WhitespaceMode.ignoreAll)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @Bindable var settings: ViewerSettings
    @State private var themes = XcodeThemeLibrary.entries()

    var body: some View {
        Form {
            Section("Colors") {
                Picker("Color scheme", selection: $settings.themePath) {
                    Text("System").tag(String?.none)
                    ForEach(themes) { theme in
                        Text(theme.name).tag(String?.some(theme.url.path(percentEncoded: false)))
                    }
                }
                Text("Xcode themes from ~/Library/Developer/Xcode/UserData/FontAndColorThemes and the selected Xcode.")
                    .settingsCaption()
            }
            Section("Text") {
                Picker("Line height", selection: $settings.lineHeightMultiple) {
                    Text("Theme").tag(0.0)
                    ForEach([0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.5, 1.75, 2.0], id: \.self) { multiple in
                        Text(multiple.formatted(.number.precision(.fractionLength(0...2))) + "×").tag(multiple)
                    }
                }
                Text("Theme follows the selected Xcode theme's line spacing, or 1× with the system colors.")
                    .settingsCaption()
                Toggle("Wrap long lines", isOn: $settings.wrapsLines)
                Toggle("Wrap at a fixed column", isOn: wrapsAtColumn)
                    .disabled(!settings.wrapsLines)
                if settings.wrapsLines, settings.wrapColumn > 0 {
                    Stepper("Column: \(settings.wrapColumn)", value: $settings.wrapColumn, in: 40...400, step: 10)
                }
                Text("In the side-by-side layout, paired rows keep the same height on both sides when lines wrap.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
        .onAppear { themes = XcodeThemeLibrary.entries() }
    }

    private var wrapsAtColumn: Binding<Bool> {
        Binding(
            get: { settings.wrapColumn > 0 },
            set: { settings.wrapColumn = $0 ? 120 : 0 }
        )
    }
}

private extension Text {
    func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
