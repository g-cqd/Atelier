/// Canonical, user-facing strings for settings that appear on more than one surface — the Settings window, the
/// toolbar's View options menu, and the Tools tab — so the three read identically (R3: labels diverging across
/// surfaces is pure extraneous load per Sweller/P1). One constant per *setting*, not per enum case: a setting's
/// picker options stay local to whichever surface renders them.
package enum SettingLabel {
    // MARK: General / Window & files

    package static let explorerPlacement = "File explorers"
    package static let treeStyle = "Arrange files as"
    package static let showsChangesOnly = "Show changed files only"
    package static let showsIgnoredFiles = "Show ignored files"
    package static let syncScrolling = "Keep panes scrolled together"
    package static let showsMinimap = "Show minimap"
    package static let showsStatusBar = "Show status bar"
    package static let autoRefresh = "Refresh automatically when files change"

    // MARK: Diff / What's compared & how it's matched

    package static let isolatesChanges = "Isolate changes"
    package static let contextLines = "Context lines"
    package static let granularity = "Highlight changes by"
    package static let whitespace = "Whitespace"
    package static let advancedMatching = "Advanced matching"
    package static let anchorsRareLines = "Anchor on rare lines"
    package static let slidesToIndentation = "Slide change boundaries by indentation"
    package static let pairsSimilarLines = "Pair changed lines by similarity"
    package static let cleansUpEmphasis = "Clean up scattered emphasis"
    package static let detectsMovedBlocks = "Mark blocks that only moved"

    // MARK: Appearance

    package static let wrapsLines = "Wrap long lines"
    package static let appearanceScheme = "Appearance"
    package static let badgeScheme = "Badge colors"
    package static let matchesThemeAppearance = "Match window appearance to theme"

    // MARK: Tools / Diagnostics

    package static let diagnosticsEnabled = "Analyze changed Swift files"
    package static let showsHoverDocumentation = "Show documentation on hover"
    package static let analyzedSides = "Analyze"
    package static let refreshToolStatus = "Refresh Tool Status"
}
