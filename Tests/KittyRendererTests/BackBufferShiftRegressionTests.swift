import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

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
