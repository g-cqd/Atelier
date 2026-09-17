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

/// Text reaches the terminal through cells; a control character in a cell would be a command, not a glyph.
struct ScreenBufferControlTests {
    @Test
    func `control characters are shown as the replacement glyph and never stored`() {
        var buffer = ScreenBuffer(columns: 12, rows: 1)
        buffer.write("a\u{1b}]52;c;\u{07}b\u{9b}c\u{7f}", row: 0, col: 0, style: .default)
        let shown = (0 ..< 12).map { buffer[0, $0].character }
        #expect(!shown.contains { ScreenBuffer.isControl($0) })
        #expect(shown.prefix(3) == ["a", "\u{FFFD}", "]"])
        #expect(shown.contains("b") && shown.contains("c"))
        #expect(ScreenBuffer.isControl("\t") && ScreenBuffer.isControl("\u{85}") && !ScreenBuffer.isControl("é"))
    }

    @Test
    func `a shift outside the buffer is refused`() {
        var buffer = ScreenBuffer(columns: 4, rows: 3)
        buffer.write("abcd", row: 2, col: 0, style: .default)
        buffer.shiftRows(regionY: 1, regionHeight: 5, regionX: 0, regionWidth: 4, delta: 1)
        buffer.shiftRows(regionY: 0, regionHeight: 3, regionX: 2, regionWidth: 4, delta: 1)
        #expect((0 ..< 4).map { buffer[2, $0].character } == ["a", "b", "c", "d"])
    }
}
