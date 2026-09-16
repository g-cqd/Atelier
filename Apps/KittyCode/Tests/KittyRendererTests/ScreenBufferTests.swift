import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct ScreenBufferTests {
    @Test
    func `Write string to buffer`() {
        var buffer = ScreenBuffer(columns: 20, rows: 5)
        let style = Style(bold: true)
        buffer.write("Hello", row: 0, col: 0, style: style)
        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 0].style.bold)
        #expect(buffer[0, 4].character == "o")
    }

    @Test
    func `Clear marks all dirty`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        buffer[0, 0] = Cell(character: "X", style: .default)
        buffer.dirty.clear()
        buffer.clear()
        #expect(buffer[0, 0].character == " ")
    }

    @Test
    func `Writing narrow text clears stale wide-character continuation cells`() {
        var buffer = ScreenBuffer(columns: 10, rows: 1)

        buffer.write("界", row: 0, col: 0, style: .default)
        buffer.dirty.clear()
        buffer.write("a", row: 0, col: 0, style: .default)

        #expect(buffer[0, 0].character == "a")
        #expect(buffer[0, 0].width == 1)
        #expect(buffer[0, 1] == .empty)
        #expect(buffer.dirty.isDirty(0))
        #expect(buffer.dirty.isDirty(1))
    }

    @Test
    func `Subscript marks dirty`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        buffer.dirty.clear()
        buffer[1, 5] = Cell(character: "A", style: .default)
        #expect(buffer.dirty.isDirty(15))  // row 1 * 10 + col 5
    }

    @Test
    func `Out of bounds reads return empty`() {
        let buffer = ScreenBuffer(columns: 10, rows: 3)

        #expect(buffer[-1, 0] == .empty)
        #expect(buffer[0, -1] == .empty)
        #expect(buffer[3, 0] == .empty)
        #expect(buffer[0, 10] == .empty)
    }

    @Test
    func `Out of bounds writes are ignored`() {
        var buffer = ScreenBuffer(columns: 5, rows: 2)

        buffer[-1, 0] = Cell(character: "X", style: .default)
        buffer[0, -1] = Cell(character: "Y", style: .default)
        buffer.write("Hello", row: -1, col: 0, style: .default)
        buffer.write("Hello", row: 2, col: 0, style: .default)
        buffer.write("Hello", row: 0, col: -1, style: .default)

        #expect(buffer.cells.allSatisfy { $0 == .empty })
        #expect(buffer.dirty.isEmpty)
    }

    @Test
    func `Out of bounds fills are ignored`() {
        var buffer = ScreenBuffer(columns: 5, rows: 2)

        buffer.fill(
            row: -1, col: 0, width: 2, height: 1, cell: Cell(character: "A", style: .default))
        buffer.fill(
            row: 0, col: -1, width: 2, height: 1, cell: Cell(character: "B", style: .default))
        buffer.fill(
            row: 2, col: 0, width: 2, height: 1, cell: Cell(character: "C", style: .default))

        #expect(buffer.cells.allSatisfy { $0 == .empty })
        #expect(buffer.dirty.isEmpty)
    }
}
