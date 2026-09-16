import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyWidgets

@Suite
struct FrameModifierTests {

    @Test
    func hstackWithFixedWidthChild() {
        let view = HStack {
            Text("A").frame(width: 3)
            Text("B")
        }
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 20, height: 1)
        ViewRenderer.render(view, into: &buffer, in: rect)

        // First child gets exactly 3 columns, second gets remainder (17)
        #expect(buffer[0, 0].character == "A")
        #expect(buffer[0, 3].character == "B")
    }

    @Test
    func vstackWithFixedHeightChild() {
        let view = VStack {
            Text("Top").frame(height: 1)
            Text("Bot")
        }
        var buffer = ScreenBuffer(columns: 10, rows: 10)
        let rect = Rect(x: 0, y: 0, width: 10, height: 10)
        ViewRenderer.render(view, into: &buffer, in: rect)

        // First child gets 1 row, second gets 9
        #expect(buffer[0, 0].character == "T")
        #expect(buffer[1, 0].character == "B")
    }

    @Test
    func nestedStacksWithMixedSizing() {
        let view = HStack {
            Text("L").frame(width: 5)
            VStack {
                Text("T").frame(height: 2)
                Text("B")
            }
        }
        var buffer = ScreenBuffer(columns: 20, rows: 10)
        let rect = Rect(x: 0, y: 0, width: 20, height: 10)
        ViewRenderer.render(view, into: &buffer, in: rect)

        // Left panel: 5 wide, right panel: 15 wide
        #expect(buffer[0, 0].character == "L")
        #expect(buffer[0, 5].character == "T")
        #expect(buffer[2, 5].character == "B")
    }

    @Test
    func separatorRendersInStack() {
        let sep = Separator(character: "|", style: .default, axis: .vertical)
        let view = HStack {
            Text("A").frame(width: 3)
            sep.frame(width: 1)
            Text("B")
        }
        var buffer = ScreenBuffer(columns: 20, rows: 3)
        let rect = Rect(x: 0, y: 0, width: 20, height: 3)
        ViewRenderer.render(view, into: &buffer, in: rect)

        #expect(buffer[0, 3].character == "|")
        #expect(buffer[1, 3].character == "|")
        #expect(buffer[2, 3].character == "|")
        #expect(buffer[0, 4].character == "B")
    }

    @Test
    func spacerPushesContent() {
        let view = HStack {
            Text("A").frame(width: 3)
            Spacer()
            Text("B").frame(width: 3)
        }
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 20, height: 1)
        ViewRenderer.render(view, into: &buffer, in: rect)

        // A at 0, spacer fills 14 cols, B at 17
        #expect(buffer[0, 0].character == "A")
        #expect(buffer[0, 17].character == "B")
    }
}
