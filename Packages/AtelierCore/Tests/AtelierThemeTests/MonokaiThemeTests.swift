import AtelierSyntaxModel
import Testing

@testable import AtelierTheme

/// The shared Monokai theme and the 8-bit colour bridge terminals use.
struct MonokaiThemeTests {
    @Test
    func `child roles inherit their parent's Monokai style`() {
        let theme = SyntaxTheme.monokai
        #expect(theme.style(for: .keywordFunction) == theme.style(for: .keyword))
        #expect(theme.style(for: .numberFloat) == theme.style(for: .number))
        #expect(theme.style(for: .typeBuiltin) == theme.style(for: .type))
        #expect(theme.style(for: .keyword).isBold)
        #expect(theme.style(for: .comment).isItalic)
    }

    @Test
    func `byte channels round-trip through the unit interval`() {
        let colour = ThemeColor(byteRed: 249, green: 38, blue: 114)
        let channels = colour.byteChannels
        #expect(channels.red == 249 && channels.green == 38 && channels.blue == 114)
        #expect(ThemeColor(red: 2, green: -1, blue: 0.5).byteChannels == (255, 0, 128))
    }
}
