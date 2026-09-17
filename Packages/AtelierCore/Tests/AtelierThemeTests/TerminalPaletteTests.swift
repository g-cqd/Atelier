import AtelierSyntaxModel
import Testing

@testable import AtelierTheme

/// A theme derived from what the terminal answers about its own colours.
struct TerminalPaletteTests {
    private let red = ThemeColor(byteRed: 200, green: 30, blue: 30)
    private let brightRed = ThemeColor(byteRed: 255, green: 80, blue: 80)
    private let green = ThemeColor(byteRed: 30, green: 200, blue: 30)
    private let magenta = ThemeColor(byteRed: 200, green: 30, blue: 200)

    private var palette: TerminalPalette {
        var ansi = [ThemeColor?](repeating: nil, count: 16)
        ansi[1] = red
        ansi[9] = brightRed
        ansi[2] = green
        ansi[5] = magenta
        return TerminalPalette(
            foreground: ThemeColor(byteRed: 230, green: 230, blue: 230),
            background: ThemeColor(byteRed: 20, green: 20, blue: 20), ansi: ansi)
    }

    @Test
    func `roles take their conventional ANSI slots, bright when known`() {
        let theme = SyntaxTheme.derived(from: palette)
        #expect(theme.style(for: .keyword).foreground == magenta)
        #expect(theme.style(for: .keyword).isBold)
        #expect(theme.style(for: .string).foreground == green)
        #expect(theme.style(for: .number).foreground == brightRed)
        #expect(theme.style(for: .tag).foreground == red)
        #expect(theme.background == palette.background)
    }

    @Test
    func `a missing slot falls back to the foreground and comments fade towards the background`() {
        let theme = SyntaxTheme.derived(from: palette)
        #expect(theme.style(for: .type).foreground == palette.foreground)
        let comment = theme.style(for: .comment).foreground ?? ThemeColor(red: 0, green: 0, blue: 0)
        #expect(comment.luminance < palette.foreground!.luminance)
        #expect(comment.luminance > palette.background!.luminance)
    }

    @Test
    func `an empty palette still derives a dark theme`() {
        let theme = SyntaxTheme.derived(from: TerminalPalette())
        #expect(theme.plainText.foreground != nil)
        #expect(TerminalPalette().isDark == nil)
        #expect(palette.isDark == true)
    }

    @Test
    func `luminance and mixing behave at the ends of the range`() {
        #expect(ThemeColor(red: 0, green: 0, blue: 0).luminance == 0)
        #expect(abs(ThemeColor(red: 1, green: 1, blue: 1).luminance - 1) < 0.001)
        let mid = ThemeColor(red: 0, green: 0, blue: 0).mixed(with: ThemeColor(red: 1, green: 1, blue: 1), amount: 0.5)
        #expect(mid == ThemeColor(red: 0.5, green: 0.5, blue: 0.5))
    }
}
