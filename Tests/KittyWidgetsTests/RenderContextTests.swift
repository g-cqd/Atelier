import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct RenderContextTests {
    @Test func `default RenderContext has nil for all properties`() {
        let context = RenderContext()

        #expect(context.foreground == nil)
        #expect(context.background == nil)
        #expect(context.bold == nil)
        #expect(context.italic == nil)
    }

    @Test func `applyTo with no overrides returns the base style unchanged`() {
        let context = RenderContext()
        let base = Style(fg: .rgb(r: 10, g: 20, b: 30), bold: true, italic: true)

        let result = context.applyTo(base)

        #expect(result == base)
    }

    @Test func `applyTo overrides foreground when context foreground is set`() {
        var context = RenderContext()
        context.foreground = .rgb(r: 255, g: 0, b: 0)
        let base = Style(fg: .rgb(r: 0, g: 0, b: 0))

        let result = context.applyTo(base)

        #expect(result.fg == .rgb(r: 255, g: 0, b: 0))
    }

    @Test func `applyTo overrides background when context background is set`() {
        var context = RenderContext()
        context.background = .rgb(r: 0, g: 0, b: 255)
        let base = Style()

        let result = context.applyTo(base)

        #expect(result.bg == .rgb(r: 0, g: 0, b: 255))
    }

    @Test func `applyTo overrides bold when context bold is set`() {
        var context = RenderContext()
        context.bold = true
        let base = Style(bold: false)

        let result = context.applyTo(base)

        #expect(result.bold == true)
    }

    @Test func `applyTo overrides italic when context italic is set`() {
        var context = RenderContext()
        context.italic = true
        let base = Style(italic: false)

        let result = context.applyTo(base)

        #expect(result.italic == true)
    }

    @Test func `merging later context wins for all set properties`() {
        var first = RenderContext()
        first.foreground = .rgb(r: 255, g: 0, b: 0)
        first.bold = true

        var second = RenderContext()
        second.foreground = .rgb(r: 0, g: 255, b: 0)
        second.italic = true

        let merged = first.merging(second)

        #expect(merged.foreground == .rgb(r: 0, g: 255, b: 0))
        #expect(merged.bold == true)
        #expect(merged.italic == true)
        #expect(merged.background == nil)
    }

    @Test func `merging with empty second context preserves first`() {
        var first = RenderContext()
        first.foreground = .rgb(r: 1, g: 2, b: 3)
        first.bold = true

        let merged = first.merging(RenderContext())

        #expect(merged.foreground == .rgb(r: 1, g: 2, b: 3))
        #expect(merged.bold == true)
    }
}
