public import AtelierTheme
public import KittyStyle

extension Style {
    /// The terminal cell style of a theme style: true colour for the foreground and background, the four
    /// emphasis flags, and the default colour where the theme leaves a channel unset.
    public init(_ style: ThemeStyle) {
        self.init(
            fg: style.foreground.map(Color.init) ?? .default,
            bg: style.background.map(Color.init) ?? .default,
            bold: style.isBold,
            italic: style.isItalic,
            underline: style.isUnderlined ? .single : .none,
            strikethrough: style.isStruckThrough
        )
    }
}

extension Color {
    /// The theme colour quantised to the terminal's 8-bit channels.
    public init(_ color: ThemeColor) {
        let channels = color.byteChannels
        self = .rgb(r: channels.red, g: channels.green, b: channels.blue)
    }
}
