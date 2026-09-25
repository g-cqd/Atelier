/// The user-facing label of every setting shown on more than one surface, so they all read identically. One
/// constant per setting; picker options stay local to the surface that renders them.
package enum SettingLabel {
    // MARK: General / Window & files

    package static let explorerPlacement = "File explorers"
    package static let treeStyle = "Arrange files as"
    package static let showsChangesOnly = "Show changed files only"
    package static let showsIgnoredFiles = "Show ignored files"
    package static let groupsByCommit = "Group changed files by commit"
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

    // MARK: Diff / Scrolling

    package static let bouncesAtEdges = "Bounce at the edges"
    package static let scrollsPastEnd = "Scroll past the last line"
    package static let scrollsToFirstChange = "Scroll to the first change when a file opens"

    // MARK: Appearance

    package static let diffLayout = "Diff layout"
    package static let compactsInlineView = "Compact inline view"
    package static let wrapsLines = "Wrap long lines"
    package static let wrapColumn = "Wrap column"
    package static let appearanceScheme = "Appearance"
    package static let badgeScheme = "Badge colors"
    package static let diffColors = "Diff colors"
    package static let matchesThemeAppearance = "Match window appearance to theme"
    package static let refinesSwiftColor = "Refine Swift color with swift-syntax"
    package static let semanticColor = "Semantic color from sourcekit-lsp"
    package static let grammarColor = "Grammar color"

    // MARK: Tools / Diagnostics

    package static let diagnosticsEnabled = "Analyze changed Swift files"
    package static let showsHoverDocumentation = "Show documentation on hover"
    package static let hoverPanelMaterial = "Hover panel material"
    package static let analyzedSides = "Analyze"
    package static let tools = "Tools"
    package static let languageServers = "Language servers"
    package static let refreshToolStatus = "Refresh Tool Status"

    // MARK: Projects

    /// The Settings window's scope selector.
    package static let settingsScope = "Settings for"
    /// The whitespace mode and the advanced matching heuristics together, as one project override.
    package static let matching = "Whitespace and matching"
}
