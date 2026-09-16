// MARK: - Color
//
// Audit D2 — the visual-style value types (`Color`, `UnderlineStyle`,
// `Style`) used to live in `KittyCodecs/Types.swift` alongside
// terminal-input value types (`KeyEvent`, `MouseButton`, …). That
// forced every syntax-highlighting consumer (`KittySyntax/Theme`,
// `RoleBasedThemeResolver`, `Highlighter`, `HighlightMerger`,
// `LanguageHighlighter`) to pull in the entire terminal-codec layer
// just to name a `Style`. They now live in this minimal module
// (`KittyStyle`) that has no dependencies and sits at the bottom of
// the layer graph. `KittyCodecs` still depends on `KittyStyle` so its
// SGR encoder + `ColorRGB` helpers continue to compile unchanged;
// syntax-side code switches its `import KittyCodecs` for
// `import KittyStyle` and stops reaching across layer boundaries.

public enum Color: Sendable, Equatable, Hashable {
    case `default`
    case indexed(UInt8)
    case rgb(r: UInt8, g: UInt8, b: UInt8)
}

// MARK: - Underline Style

public enum UnderlineStyle: UInt8, Sendable, Equatable, Hashable {
    case none = 0
    case single = 1
    case double = 2
    case curly = 3
    case dotted = 4
    case dashed = 5
}

// MARK: - Style

public struct Style: Sendable, Equatable, Hashable {
    public var fg: Color
    public var bg: Color
    public var underlineColor: Color
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: UnderlineStyle
    public var strikethrough: Bool
    public var inverse: Bool

    public static let `default` = Style()

    public init(
        fg: Color = .default,
        bg: Color = .default,
        underlineColor: Color = .default,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: UnderlineStyle = .none,
        strikethrough: Bool = false,
        inverse: Bool = false
    ) {
        self.fg = fg
        self.bg = bg
        self.underlineColor = underlineColor
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverse = inverse
    }
}
