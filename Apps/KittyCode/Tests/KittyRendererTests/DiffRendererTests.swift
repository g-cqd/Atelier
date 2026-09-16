import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct DiffRendererTests {
    @Test
    func `No dirty cells produces empty output`() {
        let buffer = ScreenBuffer(columns: 10, rows: 3)
        let front = buffer
        let output = DiffRenderer.render(front: front, back: buffer)
        #expect(output.isEmpty)
    }

    @Test
    func `Dirty cell produces cursor move plus character`() {
        var back = ScreenBuffer(columns: 10, rows: 3)
        let front = ScreenBuffer(columns: 10, rows: 3)
        back[0, 0] = Cell(character: "A", style: .default)
        let output = DiffRenderer.render(front: front, back: back)
        #expect(!output.isEmpty)
        // Should contain cursor move to 1;1 and the character A
        #expect(output.contains(0x41))  // 'A'
    }

    @Test
    func `Dirty cells matching front buffer produce no output`() {
        var front = ScreenBuffer(columns: 5, rows: 1)
        front.write("hello", row: 0, col: 0, style: .default)

        var back = front
        back.dirty.markRange(0..<5)

        let output = DiffRenderer.render(front: front, back: back)
        #expect(output.isEmpty)
    }
}
