import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct ShiftRowsTests {
    @Test
    func `Shift rows up by 1 moves content correctly`() {
        var buffer = ScreenBuffer(columns: 5, rows: 4)
        buffer.write("AAAAA", row: 0, col: 0, style: .default)
        buffer.write("BBBBB", row: 1, col: 0, style: .default)
        buffer.write("CCCCC", row: 2, col: 0, style: .default)
        buffer.write("DDDDD", row: 3, col: 0, style: .default)

        buffer.shiftRows(regionY: 0, regionHeight: 4, regionX: 0, regionWidth: 5, delta: 1)

        let row0 = (0..<5).map { buffer[0, $0].character }
        let row1 = (0..<5).map { buffer[1, $0].character }
        let row2 = (0..<5).map { buffer[2, $0].character }
        #expect(row0 == ["B", "B", "B", "B", "B"])
        #expect(row1 == ["C", "C", "C", "C", "C"])
        #expect(row2 == ["D", "D", "D", "D", "D"])
        // Row 3 retains old content (vacated row)
        #expect(buffer[3, 0].character == "D")
    }

    @Test
    func `Shift rows down by 1 moves content correctly`() {
        var buffer = ScreenBuffer(columns: 5, rows: 4)
        buffer.write("AAAAA", row: 0, col: 0, style: .default)
        buffer.write("BBBBB", row: 1, col: 0, style: .default)
        buffer.write("CCCCC", row: 2, col: 0, style: .default)
        buffer.write("DDDDD", row: 3, col: 0, style: .default)

        buffer.shiftRows(regionY: 0, regionHeight: 4, regionX: 0, regionWidth: 5, delta: -1)

        let row1 = (0..<5).map { buffer[1, $0].character }
        let row2 = (0..<5).map { buffer[2, $0].character }
        let row3 = (0..<5).map { buffer[3, $0].character }
        // Row 0 retains old content (vacated row)
        #expect(buffer[0, 0].character == "A")
        #expect(row1 == ["A", "A", "A", "A", "A"])
        #expect(row2 == ["B", "B", "B", "B", "B"])
        #expect(row3 == ["C", "C", "C", "C", "C"])
    }

    @Test
    func `Shift only affects the specified region`() {
        var buffer = ScreenBuffer(columns: 10, rows: 5)
        // Fill entire buffer with dots
        buffer.fill(
            row: 0, col: 0, width: 10, height: 5, cell: Cell(character: ".", style: .default))
        // Write distinct content in the region (cols 2..6, rows 1..3)
        buffer.write("AAAA", row: 1, col: 2, style: .default)
        buffer.write("BBBB", row: 2, col: 2, style: .default)
        buffer.write("CCCC", row: 3, col: 2, style: .default)

        buffer.shiftRows(regionY: 1, regionHeight: 3, regionX: 2, regionWidth: 4, delta: 1)

        // Row 1, cols 2..5 should now have BBBB (shifted from row 2)
        let shifted = (2..<6).map { buffer[1, $0].character }
        #expect(shifted == ["B", "B", "B", "B"])

        // Outside region: row 0 and cols 0..1 are untouched
        #expect(buffer[0, 0].character == ".")
        #expect(buffer[1, 0].character == ".")
        #expect(buffer[1, 1].character == ".")
        #expect(buffer[1, 6].character == ".")
    }

    @Test
    func `Shift by delta equal to region height is a no-op`() {
        var buffer = ScreenBuffer(columns: 5, rows: 3)
        buffer.write("ABC", row: 0, col: 0, style: .default)
        let before = buffer.cells

        buffer.shiftRows(regionY: 0, regionHeight: 3, regionX: 0, regionWidth: 5, delta: 3)

        #expect(buffer.cells == before)
    }

    @Test
    func `Shift by zero is a no-op`() {
        var buffer = ScreenBuffer(columns: 5, rows: 3)
        buffer.write("XYZ", row: 1, col: 0, style: .default)
        let before = buffer.cells

        buffer.shiftRows(regionY: 0, regionHeight: 3, regionX: 0, regionWidth: 5, delta: 0)

        #expect(buffer.cells == before)
    }

    @Test
    func `Shift does not set dirty bits`() {
        var buffer = ScreenBuffer(columns: 5, rows: 4)
        buffer.write("AAAAA", row: 0, col: 0, style: .default)
        buffer.write("BBBBB", row: 1, col: 0, style: .default)
        buffer.dirty.clear()

        buffer.shiftRows(regionY: 0, regionHeight: 4, regionX: 0, regionWidth: 5, delta: 1)

        #expect(buffer.dirty.isEmpty)
    }

    @Test
    func `Shift up by 2 moves content correctly`() {
        var buffer = ScreenBuffer(columns: 3, rows: 5)
        for r in 0..<5 {
            // swiftlint:disable:next force_unwrapping
            let ch = Character(UnicodeScalar(65 + r)!)  // A, B, C, D, E
            buffer.fill(
                row: r, col: 0, width: 3, height: 1, cell: Cell(character: ch, style: .default))
        }

        buffer.shiftRows(regionY: 0, regionHeight: 5, regionX: 0, regionWidth: 3, delta: 2)

        #expect(buffer[0, 0].character == "C")
        #expect(buffer[1, 0].character == "D")
        #expect(buffer[2, 0].character == "E")
    }
}
