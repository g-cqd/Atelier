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
