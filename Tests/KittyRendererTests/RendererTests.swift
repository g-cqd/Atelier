import Testing
@testable import KittyRenderer
@testable import KittyCodecs
@testable import KittyTerminal

@Suite
struct CellTests {
    @Test
    func `Default cell is space with default style`() {
        let cell = Cell.empty
        #expect(cell.character == " ")
        #expect(cell.style == .default)
        #expect(cell.width == 1)
    }
}

@Suite
struct DirtyTrackerTests {
    @Test
    func `Mark and check dirty`() {
        var tracker = DirtyTracker(capacity: 100)
        #expect(!tracker.isDirty(5))
        tracker.mark(5)
        #expect(tracker.isDirty(5))
        #expect(!tracker.isDirty(4))
    }

    @Test
    func `Out of bounds indices are ignored`() {
        var tracker = DirtyTracker(capacity: 10)

        tracker.mark(-1)
        tracker.mark(10)

        #expect(!tracker.isDirty(-1))
        #expect(!tracker.isDirty(10))
        #expect(tracker.isEmpty)
    }

    @Test
    func `Clear resets all bits`() {
        var tracker = DirtyTracker(capacity: 100)
        tracker.mark(0)
        tracker.mark(99)
        tracker.clear()
        #expect(tracker.isEmpty)
    }

    @Test
    func `Dirty ranges`() {
        var tracker = DirtyTracker(capacity: 30)  // 10 cols × 3 rows
        tracker.mark(10) // row 1, col 0
        tracker.mark(11) // row 1, col 1
        tracker.mark(12) // row 1, col 2
        let ranges = tracker.dirtyRanges(columns: 10)
        #expect(ranges.count == 1)
        #expect(ranges[0].row == 1)
        #expect(ranges[0].colStart == 0)
        #expect(ranges[0].colEnd == 3)
    }
}

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
        #expect(buffer.dirty.isDirty(15)) // row 1 * 10 + col 5
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

        buffer.fill(row: -1, col: 0, width: 2, height: 1, cell: Cell(character: "A", style: .default))
        buffer.fill(row: 0, col: -1, width: 2, height: 1, cell: Cell(character: "B", style: .default))
        buffer.fill(row: 2, col: 0, width: 2, height: 1, cell: Cell(character: "C", style: .default))

        #expect(buffer.cells.allSatisfy { $0 == .empty })
        #expect(buffer.dirty.isEmpty)
    }
}

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
        buffer.fill(row: 0, col: 0, width: 10, height: 5, cell: Cell(character: ".", style: .default))
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
            let ch = Character(UnicodeScalar(65 + r)!) // A, B, C, D, E
            buffer.fill(row: r, col: 0, width: 3, height: 1, cell: Cell(character: ch, style: .default))
        }

        buffer.shiftRows(regionY: 0, regionHeight: 5, regionX: 0, regionWidth: 3, delta: 2)

        #expect(buffer[0, 0].character == "C")
        #expect(buffer[1, 0].character == "D")
        #expect(buffer[2, 0].character == "E")
    }
}

@Suite
struct BeginFrameTests {
    @Test
    @MainActor
    func `beginFrame retains previous content`() {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 3)
        pipeline.buffer.write("hello", row: 0, col: 0, style: .default)

        pipeline.beginFrame()

        #expect(pipeline.buffer[0, 0].character == "h")
        #expect(pipeline.buffer[0, 4].character == "o")
    }

    @Test
    @MainActor
    func `beginFrame resets cursor position`() {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 3)
        pipeline.cursorRow = 5
        pipeline.cursorCol = 3

        pipeline.beginFrame()

        #expect(pipeline.cursorRow == nil)
        #expect(pipeline.cursorCol == nil)
    }

    @Test
    @MainActor
    func `overwriting identical content after beginFrame produces no dirty cells`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 2)

        // First frame: write content and flush
        pipeline.buffer.write("hello", row: 0, col: 0, style: .default)
        pipeline.buffer.write("world", row: 1, col: 0, style: .default)
        try pipeline.flush()

        // Second frame: same content
        pipeline.beginFrame()
        pipeline.buffer.write("hello", row: 0, col: 0, style: .default)
        pipeline.buffer.write("world", row: 1, col: 0, style: .default)

        #expect(pipeline.buffer.dirty.isEmpty)
    }

    @Test
    @MainActor
    func `only changed cells are dirty after beginFrame and partial overwrite`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 2)

        pipeline.buffer.write("aaaaaaaaaa", row: 0, col: 0, style: .default)
        pipeline.buffer.write("bbbbbbbbbb", row: 1, col: 0, style: .default)
        try pipeline.flush()

        pipeline.beginFrame()
        // Re-write row 0 identically, change row 1
        pipeline.buffer.write("aaaaaaaaaa", row: 0, col: 0, style: .default)
        pipeline.buffer.write("cccccccccc", row: 1, col: 0, style: .default)

        // Row 0: no dirty cells
        for col in 0..<10 {
            #expect(!pipeline.buffer.dirty.isDirty(col), "Row 0, col \(col) should not be dirty")
        }
        // Row 1: all cells dirty
        for col in 0..<10 {
            #expect(pipeline.buffer.dirty.isDirty(10 + col), "Row 1, col \(col) should be dirty")
        }
    }

    @Test
    @MainActor
    func `flush after scroll with pre-shift produces minimal output`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        // First frame: 4 distinct rows
        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        try pipeline.flush()
        let firstFlushSize = mock.writtenOutput.count

        // Simulate scroll down by 1: shift rows up, then write new bottom row
        pipeline.beginFrame()
        pipeline.buffer.shiftRows(regionY: 0, regionHeight: 4, regionX: 0, regionWidth: 5, delta: 1)
        // Re-write all rows as they would appear after scroll
        pipeline.buffer.write("BBBBB", row: 0, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 1, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 2, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 3, col: 0, style: .default)

        // Only row 3 should be dirty (rows 0-2 match the shifted content)
        for col in 0..<5 {
            #expect(!pipeline.buffer.dirty.isDirty(0 * 5 + col), "Row 0 col \(col) should not be dirty")
            #expect(!pipeline.buffer.dirty.isDirty(1 * 5 + col), "Row 1 col \(col) should not be dirty")
            #expect(!pipeline.buffer.dirty.isDirty(2 * 5 + col), "Row 2 col \(col) should not be dirty")
            #expect(pipeline.buffer.dirty.isDirty(3 * 5 + col), "Row 3 col \(col) should be dirty")
        }

        // Clear written output to measure only the second flush
        mock.clearOutput()
        try pipeline.flush()
        let secondFlushSize = mock.writtenOutput.count

        // Second flush should be much smaller (only 1 row vs 4)
        #expect(secondFlushSize < firstFlushSize, "Scrolled flush (\(secondFlushSize) bytes) should be smaller than full flush (\(firstFlushSize) bytes)")
    }
}

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
        #expect(output.contains(0x41)) // 'A'
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

@Suite
struct RenderPipelineTests {
    @Test
    @MainActor
    func `Flush writes to connection`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 3)
        pipeline.buffer[0, 0] = Cell(character: "X", style: .default)
        try pipeline.flush()
        #expect(!mock.writtenOutput.isEmpty)
        // Should contain sync markers
        #expect(mock.writtenOutput.starts(with: KittySequences.beginSyncUpdate))
    }
}
