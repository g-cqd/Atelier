/// How bidirectional text is handled (text-renderer.md §3.7): code stays in logical order even when a source line
/// carries directional controls, which are drawn as visible placeholders rather than left to reorder the line.
public enum BidiPolicy: Hashable, Sendable {
    /// Right-to-left letters still lay out right to left; explicit direction-control characters are ignored for
    /// ordering (`kCTTypesetterOptionForcedEmbeddingLevel = 0`) and drawn as placeholders.
    case forceLeftToRight
    /// The Unicode Bidirectional Algorithm runs unmodified.
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
