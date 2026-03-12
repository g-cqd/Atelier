import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyCode

@Suite
struct ResolvedStyleTests {
    @Test
    func `resolvedStyle returns nil for nil color`() {
        let theme = KittyConfig.Theme()
        #expect(theme.resolvedStyle(nil) == nil)
    }

    @Test
    func `resolvedStyle returns style for non-nil color`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0xff, g: 0x00, b: 0x00)
        let style = theme.resolvedStyle(color)
        #expect(style != nil)
        #expect(style?.fg == Color.rgb(r: 0xff, g: 0x00, b: 0x00))
        #expect(style?.bold == false)
    }

    @Test
    func `resolvedStyle with bold flag`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0x00, g: 0xff, b: 0x00)
        let style = theme.resolvedStyle(color, bold: true)
        #expect(style != nil)
        #expect(style?.bold == true)
    }
}
