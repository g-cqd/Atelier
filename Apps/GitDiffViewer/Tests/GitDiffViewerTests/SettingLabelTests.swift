import Testing

@testable import DiffComparison

/// ``SettingLabel``'s canonical strings. The app target's views that use them are not importable here, so the build
/// itself checks those uses.
struct SettingLabelTests {
    @Test
    func `every canonical label is non-empty and stable`() {
        let labels = [
            SettingLabel.explorerPlacement, SettingLabel.treeStyle, SettingLabel.showsChangesOnly,
            SettingLabel.showsIgnoredFiles, SettingLabel.groupsByCommit, SettingLabel.syncScrolling,
            SettingLabel.showsMinimap,
            SettingLabel.showsStatusBar, SettingLabel.isolatesChanges, SettingLabel.contextLines,
            SettingLabel.granularity, SettingLabel.whitespace, SettingLabel.advancedMatching,
            SettingLabel.anchorsRareLines, SettingLabel.slidesToIndentation, SettingLabel.pairsSimilarLines,
            SettingLabel.cleansUpEmphasis, SettingLabel.detectsMovedBlocks, SettingLabel.wrapsLines,
            SettingLabel.showsScopeRibbon,
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
