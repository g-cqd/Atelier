import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct ViewModifierContextTests {
    @Test func `foreground modifier sets foreground on RenderContext`() {
        let modifier = ForegroundModifier(color: .rgb(r: 255, g: 0, b: 0))
        let result = modifier.modifyContext(RenderContext())

        #expect(result.foreground == .rgb(r: 255, g: 0, b: 0))
        #expect(result.background == nil)
        #expect(result.bold == nil)
        #expect(result.italic == nil)
    }

    @Test func `background modifier sets background on RenderContext`() {
        let modifier = BackgroundModifier(color: .rgb(r: 0, g: 0, b: 255))
        let result = modifier.modifyContext(RenderContext())

        #expect(result.background == .rgb(r: 0, g: 0, b: 255))
        #expect(result.foreground == nil)
        #expect(result.bold == nil)
        #expect(result.italic == nil)
    }

    @Test func `bold modifier sets bold on RenderContext`() {
        let modifier = BoldModifier()
        let result = modifier.modifyContext(RenderContext())

        #expect(result.bold == true)
        #expect(result.foreground == nil)
        #expect(result.background == nil)
        #expect(result.italic == nil)
    }

    @Test func `italic modifier sets italic on RenderContext`() {
        let modifier = ItalicModifier()
        let result = modifier.modifyContext(RenderContext())

        #expect(result.italic == true)
        #expect(result.foreground == nil)
        #expect(result.background == nil)
        #expect(result.bold == nil)
    }

    @Test func `chained bold and italic modifiers accumulate on RenderContext`() {
        let base = RenderContext()
        let afterBold = BoldModifier().modifyContext(base)
        let afterBoldAndItalic = ItalicModifier().modifyContext(afterBold)

        #expect(afterBoldAndItalic.bold == true)
        #expect(afterBoldAndItalic.italic == true)
    }

    @Test func `foreground modifier does not clear a previously set bold`() {
        var base = RenderContext()
        base.bold = true
        let result = ForegroundModifier(color: .rgb(r: 100, g: 100, b: 100)).modifyContext(base)

        #expect(result.bold == true)
        #expect(result.foreground == .rgb(r: 100, g: 100, b: 100))
    }
}
