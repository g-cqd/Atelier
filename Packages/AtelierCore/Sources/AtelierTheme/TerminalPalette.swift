import AtelierSyntaxModel

/// The colours a terminal reports for its default foreground, default background and the sixteen ANSI slots,
/// in the order the slots are numbered: black, red, green, yellow, blue, magenta, cyan, white, then their
/// bright variants. A slot the terminal did not answer for is nil.
public struct TerminalPalette: Sendable, Hashable {
    public var foreground: ThemeColor?
    public var background: ThemeColor?
    public var ansi: [ThemeColor?]

    public init(foreground: ThemeColor? = nil, background: ThemeColor? = nil, ansi: [ThemeColor?] = []) {
        self.foreground = foreground
        self.background = background
        self.ansi = ansi
    }

    /// The colour in ANSI slot `index`, preferring the bright variant of a base slot when it is known.
    public func color(_ index: Int, bright: Bool = false) -> ThemeColor? {
        if bright, index < 8, index + 8 < ansi.count, let color = ansi[index + 8] { return color }
        return index < ansi.count ? ansi[index] : nil
    }

    /// Whether the background is dark, judged on its relative luminance; nil without a background.
    public var isDark: Bool? {
        background.map { $0.luminance < 0.5 }
    }
}

extension ThemeColor {
    /// Relative luminance in sRGB, 0 for black and 1 for white.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045
                ? channel / 12.92 : ((channel + 0.055) / 1.055).squareRoot() * ((channel + 0.055) / 1.055)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// This colour mixed towards `other` by `amount` in 0...1, channel by channel.
    public func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = min(max(amount, 0), 1)
        return ThemeColor(
            red: red + (other.red - red) * t, green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }
}

extension SyntaxTheme {
    /// A theme derived from the terminal's own palette, so an editor drawn with true colour matches the
    /// terminal around it: roles take the ANSI slots their conventional colours live in, comments are the
    /// foreground faded towards the background, and surfaces come from the same fade.
    ///
    /// Slots the palette lacks fall back to the foreground, so a partial answer still yields a usable theme.
    public static func derived(from palette: TerminalPalette, name: String = "Terminal") -> SyntaxTheme {
        let foreground = palette.foreground ?? ThemeColor(red: 0.85, green: 0.85, blue: 0.85)
        let background = palette.background ?? ThemeColor(red: 0.1, green: 0.1, blue: 0.1)
        func slot(_ index: Int, bright: Bool = false) -> ThemeColor {
            palette.color(index, bright: bright) ?? foreground
        }
        let faded = foreground.mixed(with: background, amount: 0.45)
        return SyntaxTheme(
            name: name,
            plainText: ThemeStyle(foreground: foreground),
            background: background,
            selection: foreground.mixed(with: background, amount: 0.8),
            roles: [
                .keyword: ThemeStyle(foreground: slot(5), isBold: true),
                .keywordOperator: ThemeStyle(foreground: slot(5)),
                .type: ThemeStyle(foreground: slot(3)),
                .function: ThemeStyle(foreground: slot(4, bright: true)),
                .functionBuiltin: ThemeStyle(foreground: slot(6)),
                .functionMacro: ThemeStyle(foreground: slot(4, bright: true), isBold: true),
                .string: ThemeStyle(foreground: slot(2)),
                .stringEscape: ThemeStyle(foreground: slot(6, bright: true)),
                .number: ThemeStyle(foreground: slot(1, bright: true)),
                .boolean: ThemeStyle(foreground: slot(1, bright: true)),
                .constant: ThemeStyle(foreground: slot(1, bright: true)),
                .comment: ThemeStyle(foreground: faded, isItalic: true),
                .commentDocumentation: ThemeStyle(foreground: faded, isItalic: true),
                .variable: ThemeStyle(foreground: foreground),
                .variableBuiltin: ThemeStyle(foreground: slot(1), isItalic: true),
                .variableParameter: ThemeStyle(foreground: foreground, isItalic: true),
                .operator: ThemeStyle(foreground: slot(5)),
                .property: ThemeStyle(foreground: slot(6)),
                .attribute: ThemeStyle(foreground: slot(3, bright: true)),
                .tag: ThemeStyle(foreground: slot(1)),
                .namespace: ThemeStyle(foreground: slot(3)),
                .label: ThemeStyle(foreground: slot(2, bright: true)),
                .constructor: ThemeStyle(foreground: slot(3)),
                .escape: ThemeStyle(foreground: slot(6, bright: true)),
                .punctuationBracket: ThemeStyle(foreground: faded.mixed(with: foreground, amount: 0.5)),
                .punctuationDelimiter: ThemeStyle(foreground: faded.mixed(with: foreground, amount: 0.5))
            ])
    }
}
