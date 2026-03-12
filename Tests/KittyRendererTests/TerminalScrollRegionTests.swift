import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

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
