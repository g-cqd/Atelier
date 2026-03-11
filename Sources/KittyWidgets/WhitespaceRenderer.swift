import KittyCodecs

public enum WhitespaceRenderer {
    public struct Config: Sendable {
        public var showIndentation: Bool
        public var showSpaces: Bool
        public var showLineBreaks: Bool
        public var showUnexpected: Bool
        public var indentationStyle: Style
        public var spaceStyle: Style
        public var lineBreakStyle: Style
        public var unexpectedStyle: Style

        public var isEnabled: Bool {
            showIndentation || showSpaces || showLineBreaks || showUnexpected
        }

        public static let disabled = Config(
            showIndentation: false,
            showSpaces: false,
            showLineBreaks: false,
            showUnexpected: false,
            indentationStyle: .default,
            spaceStyle: .default,
            lineBreakStyle: .default,
            unexpectedStyle: .default
        )

        public init(
            showIndentation: Bool,
            showSpaces: Bool,
            showLineBreaks: Bool,
            showUnexpected: Bool,
            indentationStyle: Style,
            spaceStyle: Style,
            lineBreakStyle: Style,
            unexpectedStyle: Style
        ) {
            self.showIndentation = showIndentation
            self.showSpaces = showSpaces
            self.showLineBreaks = showLineBreaks
            self.showUnexpected = showUnexpected
            self.indentationStyle = indentationStyle
            self.spaceStyle = spaceStyle
            self.lineBreakStyle = lineBreakStyle
            self.unexpectedStyle = unexpectedStyle
        }
    }

    public enum CharCategory {
        case normal
        case indentSpace
        case indentTab
        case space
        case unexpectedInvisible
    }

    @inline(__always)
    public static func classify(_ char: Character, isLeading: Bool) -> CharCategory {
        switch char {
        case " ":
            return isLeading ? .indentSpace : .space
        case "\t":
            return isLeading ? .indentTab : .space
        case "\u{00A0}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}":
            return .unexpectedInvisible
        default:
            return .normal
        }
    }

    @inline(__always)
    public static func replacementGlyph(for category: CharCategory) -> Character? {
        switch category {
        case .normal:
            return nil
        case .indentSpace:
            return "\u{00B7}" // ·
        case .indentTab:
            return "\u{2192}" // →
        case .space:
            return "\u{00B7}" // ·
        case .unexpectedInvisible:
            return "\u{2300}" // ⌀
        }
    }

    public static let lineBreakGlyph: Character = "\u{00B6}" // ¶
}
