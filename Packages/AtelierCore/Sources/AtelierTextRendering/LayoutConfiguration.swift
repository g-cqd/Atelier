/// How bidirectional text is handled (text-renderer.md §3.7): a row's base direction is set by the policy rather than
/// by its first strong character, and the direction controls that could reorder a row are drawn as placeholders.
public enum BidiPolicy: Hashable, Sendable {
    /// Every row's base direction is left to right, so a row that starts with right-to-left letters begins at the
    /// left. Right-to-left words still read right to left inside the row. The bidi controls (U+202A to U+202E,
    /// U+2066 to U+2069, U+200E, U+200F and U+061C) are drawn as placeholders of the same length (`▸`, `◂`, `↔`, `□`),
    /// which reorder nothing; the controls themselves no longer reorder the text around them (the Trojan Source class,
    /// CVE-2021-42574).
    case forceLeftToRight
    /// The Unicode Bidirectional Algorithm runs unmodified: each row takes its base direction from its first strong
    /// character, and the controls reorder the text around them.
    case unicodeDefault
}

public struct LayoutConfiguration: Hashable, Sendable {
    public enum Wrap: Hashable, Sendable {
        case none
        case width(Double)
        case columns(Int)
    }

    public var wrap: Wrap
    /// Given, never derived: the one value both backends share (text-renderer.md §1.3 finding 7).
    public var lineHeight: Double
    public var lineHeightMultiple: Double
    /// In cells.
    public var tabWidth: Int
    /// In cells, for a wrapped row's continuation lines.
    public var continuationIndent: Int
    public var padding: Double
    public var bidi: BidiPolicy

    public init(
        wrap: Wrap, lineHeight: Double, lineHeightMultiple: Double = 1, tabWidth: Int = 4,
        continuationIndent: Int = 2, padding: Double = 0, bidi: BidiPolicy = .forceLeftToRight
    ) {
        self.wrap = wrap
        self.lineHeight = lineHeight
        self.lineHeightMultiple = lineHeightMultiple
        self.tabWidth = tabWidth
        self.continuationIndent = continuationIndent
        self.padding = padding
        self.bidi = bidi
    }

    /// The line height a row of unwrapped text takes: ``lineHeight`` times ``lineHeightMultiple``.
    public var resolvedLineHeight: Double { lineHeight * lineHeightMultiple }
}
