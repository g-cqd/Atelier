import Testing
@testable import KittyRenderer
@testable import KittyCodecs
@testable import KittyTerminal

@Suite("Cell")
struct CellTests {
    @Test("Default cell is space with default style")
    func defaultCell() {
        let cell = Cell.empty
        #expect(cell.character == " ")
        #expect(cell.style == .default)
        #expect(cell.width == 1)
    }
}

@Suite("DirtyTracker")
struct DirtyTrackerTests {
    @Test("Mark and check dirty")
    func markAndCheck() {
        var tracker = DirtyTracker(capacity: 100)
        #expect(!tracker.isDirty(5))
        tracker.mark(5)
        #expect(tracker.isDirty(5))
        #expect(!tracker.isDirty(4))
    }

    @Test("Clear resets all bits")
    func clear() {
        var tracker = DirtyTracker(capacity: 100)
        tracker.mark(0)
        tracker.mark(99)
        tracker.clear()
        #expect(tracker.isEmpty)
    }

    @Test("Dirty ranges")
    func dirtyRanges() {
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

@Suite("ScreenBuffer")
struct ScreenBufferTests {
    @Test("Write string to buffer")
    func writeString() {
        var buffer = ScreenBuffer(columns: 20, rows: 5)
        let style = Style(bold: true)
        buffer.write("Hello", row: 0, col: 0, style: style)
        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 0].style.bold)
        #expect(buffer[0, 4].character == "o")
    }

    @Test("Clear marks all dirty")
    func clearBuffer() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        buffer[0, 0] = Cell(character: "X", style: .default)
        buffer.dirty.clear()
        buffer.clear()
        #expect(buffer[0, 0].character == " ")
    }

    @Test("Subscript marks dirty")
    func subscriptDirty() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        buffer.dirty.clear()
        buffer[1, 5] = Cell(character: "A", style: .default)
        #expect(buffer.dirty.isDirty(15)) // row 1 * 10 + col 5
    }
}

@Suite("DiffRenderer")
struct DiffRendererTests {
    @Test("No dirty cells produces empty output")
    func noDirty() {
        let buffer = ScreenBuffer(columns: 10, rows: 3)
        let front = buffer
        let output = DiffRenderer.render(front: front, back: buffer)
        #expect(output.isEmpty)
    }

    @Test("Dirty cell produces cursor move + character")
    func dirtyCell() {
        var back = ScreenBuffer(columns: 10, rows: 3)
        let front = ScreenBuffer(columns: 10, rows: 3)
        back[0, 0] = Cell(character: "A", style: .default)
        let output = DiffRenderer.render(front: front, back: back)
        #expect(!output.isEmpty)
        // Should contain cursor move to 1;1 and the character A
        #expect(output.contains(0x41)) // 'A'
    }
}

@Suite("RenderPipeline")
struct RenderPipelineTests {
    @Test("Flush writes to connection")
    func flushWrites() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 10, rows: 3)
        pipeline.buffer[0, 0] = Cell(character: "X", style: .default)
        try pipeline.flush()
        #expect(!mock.writtenOutput.isEmpty)
        // Should contain sync markers
        #expect(mock.writtenOutput.starts(with: KittySequences.beginSyncUpdate))
    }
}
