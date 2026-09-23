// MARK: - Color
//
// The style value types sit in this dependency-free module so syntax code can name a `Style` without the codecs.

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
