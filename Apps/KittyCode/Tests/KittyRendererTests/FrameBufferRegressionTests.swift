import Testing

@testable import KittyRenderer
@testable import KittyStyle
@testable import KittyTerminal

@Suite
@MainActor
struct FrameBufferRegressionTests {
    private func captureFrames() throws -> (bytes: [[UInt8]], dirtyCounts: [Int]) {
        let terminal = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: terminal, columns: 6, rows: 4)
        var bytes: [[UInt8]] = []
        var dirtyCounts: [Int] = []

        func capture() throws {
            dirtyCounts.append(
                pipeline.buffer.dirty.dirtyRanges(columns: pipeline.columns)
                    .reduce(0) {
                        $0 + $1.colEnd - $1.colStart
                    })
            terminal.clearOutput()
            try pipeline.flush()
            bytes.append(terminal.writtenOutput)
        }

        pipeline.buffer.write("ABCDEF", row: 0, col: 0, style: .default)
        pipeline.buffer.write("ghijkl", row: 1, col: 0, style: .default)
        pipeline.buffer.write("mnopqr", row: 2, col: 0, style: .default)
        pipeline.buffer.write("STUVWX", row: 3, col: 0, style: .default)
        try capture()

        pipeline.beginFrame()
        pipeline.buffer.write("ABXDEF", row: 0, col: 0, style: .default)
        pipeline.buffer.write("ghijkl", row: 1, col: 0, style: .default)
        pipeline.buffer.write("READY!", row: 3, col: 0, style: .default)
        try capture()

        pipeline.beginFrame()
        pipeline.scrollHint = ScrollHint(regionTop: 1, regionHeight: 3, delta: 1)
        pipeline.buffer.write("mnopqr", row: 1, col: 0, style: .default)
        pipeline.buffer.write("READY!", row: 2, col: 0, style: .default)
        pipeline.buffer.write("next!!", row: 3, col: 0, style: .default)
        try capture()

        pipeline.beginFrame()
        pipeline.buffer.write("line 1", row: 1, col: 0, style: .default)
        pipeline.buffer.write("line 2", row: 2, col: 0, style: .default)
        pipeline.buffer.write("new   ", row: 3, col: 0, style: .default)
        try capture()

        return (bytes, dirtyCounts)
    }

    @Test
    func `chrome page and Enter frames keep their exact bytes`() throws {
        let frames = try captureFrames()
        let expected = [
            "\u{1B}[?2026h\u{1B}[?25l\u{1B}[1;1HABCDEF\u{1B}[2;1Hghijkl\u{1B}[3;1Hmnopqr\u{1B}[4;1HSTUVWX\u{1B}[?25l\u{1B}[?2026l",
            "\u{1B}[?2026h\u{1B}[?25l\u{1B}[1;3HX\u{1B}[4;1HREADY!\u{1B}[?25l\u{1B}[?2026l",
            "\u{1B}[?2026h\u{1B}[2;4r\u{1B}[1S\u{1B}[r\u{1B}[?25l\u{1B}[4;1Hnext!!\u{1B}[?25l\u{1B}[?2026l",
            "\u{1B}[?2026h\u{1B}[?25l\u{1B}[2;1Hline 1\u{1B}[3;1Hline 2\u{1B}[4;3Hw   \u{1B}[?25l\u{1B}[?2026l"
        ]
        .map { Array($0.utf8) }
        #expect(frames.bytes == expected)
    }

    @Test
    func `chrome page and Enter frames keep their dirty cell counts`() throws {
        let frames = try captureFrames()
        #expect(frames.dirtyCounts == [24, 7, 17, 16])
    }

    @Test
    func `forced redraw leaves the next diff byte identical`() throws {
        let terminal = MockTerminalConnection()
        let pipeline = RenderPipeline(connection: terminal, columns: 3, rows: 1)
        pipeline.buffer.write("ABC", row: 0, col: 0, style: .default)
        try pipeline.forceRedraw()
        #expect(terminal.writtenOutput == Array("\u{1B}[?2026h\u{1B}[?25l\u{1B}[1;1HABC\u{1B}[?2026l".utf8))

        pipeline.buffer[0, 1] = Cell(character: "X", style: .default)
        terminal.clearOutput()
        try pipeline.flush()
        #expect(terminal.writtenOutput == Array("\u{1B}[?2026h\u{1B}[?25l\u{1B}[1;2HX\u{1B}[?25l\u{1B}[?2026l".utf8))
    }
}
