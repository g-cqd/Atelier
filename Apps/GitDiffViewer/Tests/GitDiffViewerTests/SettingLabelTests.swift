import Testing

@testable import DiffComparison

/// ``SettingLabel`` (R3): one canonical string per setting, referenced from the Settings window, the Tools tab
/// and the View options menu so the three read identically. The app target's views cannot be imported here (the
/// test target only depends on the library targets, not the `GitDiffViewer` executable), so this asserts the
/// constants exist with the exact strings those surfaces build against; `swift build` covers the compile-level
/// check that `SettingsView.swift`, `ToolsSettings.swift` and `ViewOptionsMenu.swift` all use them.
struct SettingLabelTests {
    @Test
    func `every canonical label is non-empty and stable`() {
        let labels = [
            SettingLabel.explorerPlacement, SettingLabel.treeStyle, SettingLabel.showsChangesOnly,
            SettingLabel.showsIgnoredFiles, SettingLabel.syncScrolling, SettingLabel.showsMinimap,
            SettingLabel.showsStatusBar, SettingLabel.isolatesChanges, SettingLabel.contextLines,
            SettingLabel.granularity, SettingLabel.whitespace, SettingLabel.advancedMatching,
            SettingLabel.anchorsRareLines, SettingLabel.slidesToIndentation, SettingLabel.pairsSimilarLines,
            SettingLabel.cleansUpEmphasis, SettingLabel.detectsMovedBlocks, SettingLabel.wrapsLines,
            SettingLabel.diagnosticsEnabled, SettingLabel.showsHoverDocumentation, SettingLabel.analyzedSides,
            SettingLabel.refreshToolStatus, SettingLabel.appearanceScheme
        ]

        #expect(labels.allSatisfy { !$0.isEmpty })
        // Every setting's label is distinct: no two settings should ever read the same on screen.
        #expect(Set(labels).count == labels.count)
    }

    @Test
    func `sync scrolling reads the same, clearer phrasing picked for both surfaces`() {
        #expect(SettingLabel.syncScrolling == "Keep panes scrolled together")
    }
}
