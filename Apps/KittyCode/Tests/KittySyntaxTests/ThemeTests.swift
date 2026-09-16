import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

@Suite
struct ThemeTests {
    @Test
    func `Exact capture match`() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "keyword") == style)
    }

    @Test
    func `Hierarchical fallback`() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        // keyword.function should fallback to keyword
        #expect(theme.style(for: "keyword.function") == style)
    }

    @Test
    func `Default style fallback`() {
        let theme = Theme(defaultStyle: Style(fg: .rgb(r: 128, g: 128, b: 128)))
        #expect(theme.style(for: "nonexistent") == theme.defaultStyle)
    }

    @Test
    func `at prefix is stripped`() {
        var theme = Theme()
        let style = Style(bold: true)
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "@keyword") == style)
    }

    @Test
    func `Monokai theme has common captures`() {
        let theme = Theme.monokai
        let kwStyle = theme.style(for: "keyword")
        #expect(kwStyle.bold)
    }
}
