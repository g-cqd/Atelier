import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

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
        for col in 0 ..< 10 {
            #expect(!pipeline.buffer.dirty.isDirty(col), "Row 0, col \(col) should not be dirty")
        }
        // Row 1: all cells dirty
        for col in 0 ..< 10 {
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
        for col in 0 ..< 5 {
            #expect(
                !pipeline.buffer.dirty.isDirty(0 * 5 + col), "Row 0 col \(col) should not be dirty")
            #expect(
                !pipeline.buffer.dirty.isDirty(1 * 5 + col), "Row 1 col \(col) should not be dirty")
            #expect(
                !pipeline.buffer.dirty.isDirty(2 * 5 + col), "Row 2 col \(col) should not be dirty")
            #expect(pipeline.buffer.dirty.isDirty(3 * 5 + col), "Row 3 col \(col) should be dirty")
        }

        // Clear written output to measure only the second flush
        mock.clearOutput()
        try pipeline.flush()
        let secondFlushSize = mock.writtenOutput.count

        // Second flush should be much smaller (only 1 row vs 4)
        #expect(
            secondFlushSize < firstFlushSize,
            "Scrolled flush (\(secondFlushSize) bytes) should be smaller than full flush (\(firstFlushSize) bytes)"
        )
    }
}
