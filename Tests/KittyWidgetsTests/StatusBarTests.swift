import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct StatusBarTests {
    @Test
    func `Render fixed width`() {
        let bar = StatusBar(left: "L", center: "C", right: "R")
        let rendered = bar.render(width: 30)
        #expect(rendered.count == 30)
    }

    @Test
    func `Non positive width returns empty string`() {
        let bar = StatusBar(left: "L", center: "C", right: "R")

        #expect(bar.render(width: 0).isEmpty)
        #expect(bar.render(width: -1).isEmpty)
    }

    @Test
    func `Edge-aligned rendering preserves the trailing segment`() {
        let bar = StatusBar(left: "left side", right: "RIGHT")
        let rendered = bar.render(width: 14)

        #expect(rendered.count == 14)
        #expect(rendered.hasSuffix("RIGHT"))
    }
}
