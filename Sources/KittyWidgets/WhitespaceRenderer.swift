import KittyCodecs

public enum WhitespaceRenderer {
    /// Controls which whitespace categories are revealed inside a selection.
    public enum SelectionVisibility: Sendable {
        /// Don't reveal any extra whitespace in selections.
        case none
        /// Reveal leading indentation (spaces/tabs) only.
        case indentation
        /// Reveal indentation + mid-line/trailing spaces.
        case all
        /// Reveal indentation + spaces + line-break markers.
        case boundary
    }

    public struct Config: Sendable {
        public var showIndentation: Bool
        public var showSpaces: Bool
        public var showLineBreaks: Bool
        public var showUnexpected: Bool
        public var selectionVisibility: SelectionVisibility
        public var indentationStyle: Style
        public var spaceStyle: Style
        public var lineBreakStyle: Style
        public var unexpectedStyle: Style

        public var isEnabled: Bool {
            showIndentation || showSpaces || showLineBreaks || showUnexpected
        }

        /// Whether selection-based whitespace rendering is active.
        public var hasSelectionVisibility: Bool {
            selectionVisibility != .none
        }

        /// Returns `true` if indentation should be shown for the given character,
        /// considering both the global flag and selection state.
        @inline(__always)
        public func shouldShowIndentation(inSelection: Bool) -> Bool {
            showIndentation || (inSelection && (selectionVisibility == .indentation || selectionVisibility == .all || selectionVisibility == .boundary))
        }

        /// Returns `true` if spaces should be shown for the given character,
        /// considering both the global flag and selection state.
        @inline(__always)
        public func shouldShowSpaces(inSelection: Bool) -> Bool {
            showSpaces || (inSelection && (selectionVisibility == .all || selectionVisibility == .boundary))
        }

        /// Returns `true` if line breaks should be shown,
        /// considering both the global flag and selection state.
        @inline(__always)
        public func shouldShowLineBreaks(inSelection: Bool) -> Bool {
            showLineBreaks || (inSelection && selectionVisibility == .boundary)
        }

        /// Whether whitespace rendering should be active at all (globally or via selection).
        public var isEnabledOrSelectionAware: Bool {
            isEnabled || hasSelectionVisibility
        }

        public static let disabled = Config(
            showIndentation: false,
            showSpaces: false,
            showLineBreaks: false,
            showUnexpected: false,
            selectionVisibility: .none,
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
            selectionVisibility: SelectionVisibility = .none,
            indentationStyle: Style,
            spaceStyle: Style,
            lineBreakStyle: Style,
            unexpectedStyle: Style
        ) {
            self.showIndentation = showIndentation
            self.showSpaces = showSpaces
            self.showLineBreaks = showLineBreaks
            self.showUnexpected = showUnexpected
            self.selectionVisibility = selectionVisibility
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
