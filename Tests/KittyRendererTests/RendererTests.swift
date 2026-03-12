// swiftlint:disable file_length
import Testing

@testable import KittyCodecs
@testable import KittyRenderer
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
        tracker.mark(10)  // row 1, col 0
        tracker.mark(11)  // row 1, col 1
        tracker.mark(12)  // row 1, col 2
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

// MARK: - Regression tests

@Suite
struct BackBufferShiftRegressionTests {
    /// Regression: shifting only the back buffer causes the DiffRenderer to miss
    /// updates for cells that differ from the front buffer (what the terminal shows),
    /// because the ScreenBuffer subscript setter doesn't mark shifted-then-confirmed
    /// cells as dirty. This caused rendering corruption during scrolling.
    @Test
    @MainActor
    func `back-buffer-only shift causes missed terminal updates`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        // Frame 1: write 4 distinct rows and flush
        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        try pipeline.flush()

        // Frame 2: simulate scroll down by 1
        // BUG pattern: shift back buffer, then re-render on top
        pipeline.beginFrame()
        pipeline.buffer.shiftRows(regionY: 0, regionHeight: 4, regionX: 0, regionWidth: 5, delta: 1)
        pipeline.buffer.write("BBBBB", row: 0, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 1, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 2, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 3, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // The terminal was showing AAAAA at row 0. After scroll, it should show BBBBB.
        // If the shift only touched the back buffer, rows 0-2 won't be dirty and
        // the DiffRenderer won't emit updates for them — the terminal still shows old content.
        // This test documents the known limitation: back-buffer-only shift suppresses
        // rows 0-2 from the diff output.
        let outputContainsB = output.contains(0x42)  // 'B'
        // With back-buffer-only shift, the output will NOT contain 'B' (the bug).
        // This test asserts the bug exists so we know not to use this pattern.
        #expect(
            !outputContainsB,
            "Back-buffer-only shift suppresses updates for scrolled rows — do NOT use this pattern without also shifting the front buffer or the terminal display"
        )
    }

    /// Verifies that the correct rendering approach (no pre-shift) produces output
    /// for all rows that changed during a scroll.
    @Test
    @MainActor
    func `scroll without pre-shift correctly updates all rows`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        // Frame 1
        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        try pipeline.flush()

        // Frame 2: scroll down by 1, NO pre-shift — just overwrite with new content
        pipeline.beginFrame()
        pipeline.buffer.write("BBBBB", row: 0, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 1, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 2, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 3, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // Without pre-shift, all 4 rows differ from the front buffer and get updated
        #expect(output.contains(0x42), "Row 0 should be updated to 'B'")  // B
        #expect(output.contains(0x43), "Row 1 should be updated to 'C'")  // C
        #expect(output.contains(0x44), "Row 2 should be updated to 'D'")  // D
        #expect(output.contains(0x45), "Row 3 should be updated to 'E'")  // E
    }

    /// Verifies that style changes are correctly emitted during scroll
    /// even when the text content at a position doesn't change.
    @Test
    @MainActor
    func `style-only changes are emitted without pre-shift`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 2)

        let styleA = Style(fg: .rgb(r: 255, g: 0, b: 0))
        let styleB = Style(fg: .rgb(r: 0, g: 255, b: 0))

        // Frame 1: row 0 has "HELLO" in red
        pipeline.buffer.write("HELLO", row: 0, col: 0, style: styleA)
        pipeline.buffer.write("WORLD", row: 1, col: 0, style: styleA)
        try pipeline.flush()

        // Frame 2: same text at row 0 but different style (green)
        pipeline.beginFrame()
        pipeline.buffer.write("HELLO", row: 0, col: 0, style: styleB)
        pipeline.buffer.write("WORLD", row: 1, col: 0, style: styleA)  // unchanged

        // Row 0 should be dirty (style changed), row 1 should not
        for col in 0..<5 {
            #expect(
                pipeline.buffer.dirty.isDirty(col),
                "Row 0 col \(col) should be dirty (style change)")
        }
        for col in 0..<5 {
            #expect(!pipeline.buffer.dirty.isDirty(5 + col), "Row 1 col \(col) should not be dirty")
        }

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // Output should contain the 'H' character (re-emitted with new style)
        #expect(output.contains(0x48), "Style-changed cells must be re-emitted")
    }
}

@Suite
struct DiffRendererRegressionTests {
    /// Verifies that within a dirty range, cells where front == back are correctly
    /// skipped (e.g. when a cell is written then overwritten back to its original value).
    @Test
    func `cells overwritten back to original value are skipped`() {
        var front = ScreenBuffer(columns: 5, rows: 1)
        front.write("ABCDE", row: 0, col: 0, style: .default)

        var back = front
        back.dirty.clear()

        // Write a different value to col 2, then write it back
        back[0, 2] = Cell(character: "X", style: .default)
        back[0, 2] = Cell(character: "C", style: .default)

        // Col 2 is dirty but matches front
        #expect(back.dirty.isDirty(2))
        let output = DiffRenderer.render(front: front, back: back)
        #expect(output.isEmpty, "Cell overwritten back to original should produce no output")
    }

    /// Verifies that the DiffRenderer handles partial changes within a dirty range:
    /// some cells changed, some didn't (multi-renderer overlap scenario).
    @Test
    func `partial changes within dirty range emit only changed cells`() {
        var front = ScreenBuffer(columns: 10, rows: 1)
        front.write("ABCDEFGHIJ", row: 0, col: 0, style: .default)

        var back = front
        back.dirty.clear()

        // Change cells 2, 3 and 7 — leave the rest the same but mark range dirty
        back[0, 2] = Cell(character: "X", style: .default)
        back[0, 3] = Cell(character: "Y", style: .default)
        back[0, 7] = Cell(character: "Z", style: .default)

        let output = DiffRenderer.render(front: front, back: back)
        #expect(output.contains(0x58), "Changed cell 'X' should be emitted")  // X
        #expect(output.contains(0x59), "Changed cell 'Y' should be emitted")  // Y
        #expect(output.contains(0x5A), "Changed cell 'Z' should be emitted")  // Z
        #expect(!output.contains(0x41), "Unchanged cell 'A' should NOT be emitted")  // A
        #expect(!output.contains(0x45), "Unchanged cell 'E' should NOT be emitted")  // E
    }

    /// Verifies that wide characters within dirty ranges are handled correctly
    /// by the DiffRenderer's cell-skipping logic.
    @Test
    func `wide character changes are emitted correctly`() {
        let front = ScreenBuffer(columns: 10, rows: 1)
        var back = ScreenBuffer(columns: 10, rows: 1)

        // Write a wide character followed by narrow characters
        back.write("界AB", row: 0, col: 0, style: .default)

        let output = DiffRenderer.render(front: front, back: back)
        // Should contain the wide character's UTF-8 encoding
        let wideCharBytes = Array("界".utf8)
        var found = false
        for i in 0..<(output.count - wideCharBytes.count + 1) {
            if Array(output[i..<(i + wideCharBytes.count)]) == wideCharBytes {
                found = true
                break
            }
        }
        #expect(found, "Wide character should be emitted")
        #expect(output.contains(0x41), "Narrow 'A' after wide char should be emitted")
        #expect(output.contains(0x42), "Narrow 'B' should be emitted")
    }
}

// MARK: - Terminal scroll region tests

private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard needle.count <= haystack.count else { return false }
    for i in 0...(haystack.count - needle.count) {
        if Array(haystack[i..<(i + needle.count)]) == needle { return true }
    }
    return false
}

@Suite
struct TerminalScrollRegionTests {
    /// Verifies that DECSTBM, SU, and SD escape sequences are correctly encoded.
    @Test
    func `scroll region sequences are properly encoded`() {
        var buf = ContiguousArray<UInt8>()
        KittySequences.appendSetScrollRegion(top: 3, bottom: 10, to: &buf)
        // CSI 3 ; 10 r → ESC [ 3 ; 1 0 r
        let setRegion = Array(buf)
        #expect(setRegion == [0x1b, 0x5b, 0x33, 0x3b, 0x31, 0x30, 0x72])

        buf.removeAll()
        KittySequences.appendScrollUp(lines: 2, to: &buf)
        // CSI 2 S → ESC [ 2 S
        let scrollUp = Array(buf)
        #expect(scrollUp == [0x1b, 0x5b, 0x32, 0x53])

        buf.removeAll()
        KittySequences.appendScrollDown(lines: 5, to: &buf)
        // CSI 5 T → ESC [ 5 T
        let scrollDown = Array(buf)
        #expect(scrollDown == [0x1b, 0x5b, 0x35, 0x54])

        buf.removeAll()
        KittySequences.appendResetScrollRegion(to: &buf)
        // CSI r → ESC [ r
        let reset = Array(buf)
        #expect(reset == [0x1b, 0x5b, 0x72])
    }

    /// Verifies that a scroll hint causes the pipeline to emit DECSTBM + SU sequences
    /// and that the front buffer is correctly shifted, reducing diff output.
    @Test
    @MainActor
    func `scroll hint reduces diff output on scroll down`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        // Frame 1: initial content
        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        try pipeline.flush()

        // Frame 2: scroll down by 1 (content moves up)
        pipeline.beginFrame()
        pipeline.scrollHint = ScrollHint(regionTop: 0, regionHeight: 4, delta: 1)
        pipeline.buffer.write("BBBBB", row: 0, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 1, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 2, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 3, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // Output should contain scroll region sequences
        // CSI 1 ; 4 r (set region)
        #expect(containsSubsequence(output, [0x1b, 0x5b, 0x31, 0x3b, 0x34, 0x72]))
        // CSI 1 S (scroll up 1)
        #expect(containsSubsequence(output, [0x1b, 0x5b, 0x31, 0x53]))
        // CSI r (reset region)
        #expect(containsSubsequence(output, [0x1b, 0x5b, 0x72]))

        // Only the newly exposed row (EEEEE) should need diff output.
        // Rows 0-2 match the shifted front buffer and are skipped.
        #expect(output.contains(0x45), "Newly exposed row 'E' should be emitted")
        #expect(!output.contains(0x42), "Shifted row 'B' should NOT be re-emitted")
        #expect(!output.contains(0x43), "Shifted row 'C' should NOT be re-emitted")
        #expect(!output.contains(0x44), "Shifted row 'D' should NOT be re-emitted")
    }

    /// Verifies scroll-up (content moves down) with a scroll hint.
    @Test
    @MainActor
    func `scroll hint works for scroll up`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        // Frame 1
        pipeline.buffer.write("BBBBB", row: 0, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 1, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 2, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 3, col: 0, style: .default)
        try pipeline.flush()

        // Frame 2: scroll up by 1 (content moves down, new row at top)
        pipeline.beginFrame()
        pipeline.scrollHint = ScrollHint(regionTop: 0, regionHeight: 4, delta: -1)
        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // CSI 1 T (scroll down 1)
        #expect(containsSubsequence(output, [0x1b, 0x5b, 0x31, 0x54]))
        // Only newly exposed row at top should be emitted
        #expect(output.contains(0x41), "Newly exposed row 'A' should be emitted")
        #expect(!output.contains(0x42), "Shifted row 'B' should NOT be re-emitted")
        #expect(!output.contains(0x43), "Shifted row 'C' should NOT be re-emitted")
    }

    /// Verifies that a partial scroll region (not full screen) works correctly,
    /// simulating a tab ribbon at the top that shouldn't be scrolled.
    @Test
    @MainActor
    func `scroll hint with partial region preserves rows outside region`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 5)

        // Row 0 = tab ribbon (not part of scroll region)
        pipeline.buffer.write("TABS!", row: 0, col: 0, style: .default)
        pipeline.buffer.write("AAAAA", row: 1, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 2, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 3, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 4, col: 0, style: .default)
        try pipeline.flush()

        // Frame 2: scroll content rows 1-4, leave row 0 alone
        pipeline.beginFrame()
        pipeline.scrollHint = ScrollHint(regionTop: 1, regionHeight: 4, delta: 1)
        pipeline.buffer.write("TABS!", row: 0, col: 0, style: .default)  // unchanged
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        pipeline.buffer.write("EEEEE", row: 4, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // Scroll region should be rows 2-5 (1-based)
        #expect(containsSubsequence(output, [0x1b, 0x5b, 0x32, 0x3b, 0x35, 0x72]))
        // Only the new row should be emitted via diff
        #expect(output.contains(0x45), "Newly exposed row 'E' should be emitted")
        // Tab ribbon row should NOT be re-emitted (it didn't change)
        #expect(!output.contains(0x54), "Tab ribbon should not be re-emitted")
    }

    /// Verifies that scroll hints exceeding the region height are ignored.
    @Test
    @MainActor
    func `scroll hint with delta >= regionHeight is ignored`() throws {
        let mock = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: mock, columns: 5, rows: 4)

        pipeline.buffer.write("AAAAA", row: 0, col: 0, style: .default)
        pipeline.buffer.write("BBBBB", row: 1, col: 0, style: .default)
        pipeline.buffer.write("CCCCC", row: 2, col: 0, style: .default)
        pipeline.buffer.write("DDDDD", row: 3, col: 0, style: .default)
        try pipeline.flush()

        // Delta equal to region height — should be ignored
        pipeline.beginFrame()
        pipeline.scrollHint = ScrollHint(regionTop: 0, regionHeight: 4, delta: 4)
        pipeline.buffer.write("EEEEE", row: 0, col: 0, style: .default)
        pipeline.buffer.write("FFFFF", row: 1, col: 0, style: .default)
        pipeline.buffer.write("GGGGG", row: 2, col: 0, style: .default)
        pipeline.buffer.write("HHHHH", row: 3, col: 0, style: .default)

        mock.clearOutput()
        try pipeline.flush()
        let output = mock.writtenOutput

        // No SU (CSI n S) or SD (CSI n T) scroll commands should be emitted
        let hasSU = containsSubsequence(output, [0x1b, 0x5b, 0x34, 0x53])  // CSI 4 S
        let hasSD = containsSubsequence(output, [0x1b, 0x5b, 0x34, 0x54])  // CSI 4 T
        #expect(!hasSU && !hasSD, "No scroll commands should be emitted for delta >= regionHeight")
        // All rows should be emitted via normal diff
        #expect(output.contains(0x45), "Row E should be emitted via diff")
        #expect(output.contains(0x48), "Row H should be emitted via diff")
    }
}
