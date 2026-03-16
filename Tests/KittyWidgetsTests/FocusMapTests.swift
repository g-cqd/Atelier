import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyWidgets

@Suite
struct FocusMapTests {

    @Test
    func hitTestNonOverlapping() {
        var map = FocusMap()
        map.register(.sidebar, rect: Rect(x: 0, y: 0, width: 10, height: 20))
        map.register(.editor, rect: Rect(x: 10, y: 0, width: 50, height: 20))

        #expect(map.hitTest(row: 5, col: 3) == .sidebar)
        #expect(map.hitTest(row: 5, col: 15) == .editor)
        #expect(map.hitTest(row: 25, col: 5) == nil)
    }

    @Test
    func hitTestOverlapping() {
        var map = FocusMap()
        map.register(.editor, rect: Rect(x: 0, y: 0, width: 80, height: 24))
        map.register(.overlay, rect: Rect(x: 10, y: 5, width: 20, height: 10))

        // Overlapping area: last registered wins
        #expect(map.hitTest(row: 8, col: 15) == .overlay)
        // Non-overlapping area
        #expect(map.hitTest(row: 0, col: 0) == .editor)
    }

    @Test
    func hitTestEmpty() {
        let map = FocusMap()
        #expect(map.hitTest(row: 0, col: 0) == nil)
    }

    @Test
    func collectorBuilds() {
        let collector = FocusMapCollector()
        collector.register(.activityBar, rect: Rect(x: 0, y: 0, width: 3, height: 20))
        collector.register(.statusBar, rect: Rect(x: 0, y: 23, width: 80, height: 1))

        let map = collector.build()
        #expect(map.entries.count == 2)
        #expect(map.hitTest(row: 10, col: 1) == .activityBar)
        #expect(map.hitTest(row: 23, col: 40) == .statusBar)
    }

    @Test
    func renderContextValueBag() {
        var ctx = RenderContext()
        ctx.set(Int.self, value: 42)
        ctx.set(String.self, value: "hello")

        #expect(ctx.get(Int.self) == 42)
        #expect(ctx.get(String.self) == "hello")
        #expect(ctx.get(Double.self) == nil)
    }

    @Test
    func renderContextMergingPreservesValues() {
        var base = RenderContext()
        base.set(Int.self, value: 1)
        base.isFocused = false

        var overlay = RenderContext()
        overlay.set(String.self, value: "test")
        overlay.isFocused = true

        let merged = base.merging(overlay)
        #expect(merged.get(Int.self) == 1)
        #expect(merged.get(String.self) == "test")
        #expect(merged.isFocused == true)
    }

    @Test
    func renderContextMergingDoesNotClobberFocusWithDefault() {
        var base = RenderContext()
        base.isFocused = true

        let fresh = RenderContext()  // isFocused is nil by default
        let merged = base.merging(fresh)
        #expect(merged.isFocused == true)
    }

    @Test
    func focusRegionModifierInnerOrderRegisters() {
        // .focusRegion() is inner, .frame() is outer — should still register
        let collector = FocusMapCollector()
        var context = RenderContext()
        context.focusMap = collector

        let view = HStack {
            Text("Side").focusRegion(.sidebar).frame(width: 10)
            Text("Edit")
        }

        var buffer = ScreenBuffer(columns: 40, rows: 5)
        let rect = Rect(x: 0, y: 0, width: 40, height: 5)
        ViewRenderer.render(view, into: &buffer, in: rect, context: context)

        let map = collector.build()
        #expect(map.hitTest(row: 2, col: 5) == .sidebar)
    }

    @Test
    func frameModifierInnerOrderUsesLayoutDimension() {
        // .frame(width:) is inner, .focusRegion() is outer — layout should still respect fixed width
        let view = HStack {
            Text("A").frame(width: 5).focusRegion(.sidebar)
            Text("B")
        }
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 20, height: 1)
        ViewRenderer.render(view, into: &buffer, in: rect)

        // First child should get 5 columns, second gets 15
        #expect(buffer[0, 0].character == "A")
        #expect(buffer[0, 5].character == "B")
    }

    @Test
    func focusRegionModifierRegistersDuringRender() {
        let collector = FocusMapCollector()
        var context = RenderContext()
        context.focusMap = collector

        let view = HStack {
            Text("Side").frame(width: 10).focusRegion(.sidebar)
            Text("Edit").focusRegion(.editor)
        }

        var buffer = ScreenBuffer(columns: 40, rows: 5)
        let rect = Rect(x: 0, y: 0, width: 40, height: 5)
        ViewRenderer.render(view, into: &buffer, in: rect, context: context)

        let map = collector.build()
        #expect(map.hitTest(row: 2, col: 5) == .sidebar)
        #expect(map.hitTest(row: 2, col: 20) == .editor)
    }
}
