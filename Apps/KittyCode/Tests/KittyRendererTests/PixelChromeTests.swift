import KittyCodecs
import KittyTerminal
import Testing

@testable import KittyRenderer

/// One-pixel lines placed under the cells, transmitted once and re-placed only when they move.
struct PixelChromeTests {
    private let cell = TerminalCapabilities.CellPixelSize(width: 10, height: 20)
    private let grey = ColorRGB(r: 48, g: 54, b: 61)

    private func commands(_ bytes: ContiguousArray<UInt8>) -> [String] {
        String(decoding: bytes, as: UTF8.self).split(separator: "\u{1b}", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("_G") }.map { String($0.dropFirst(2).prefix { $0 != ";" }) }
    }

    @Test
    func `a vertical line transmits a 1 by N image once and places it under the text`() {
        var chrome = PixelChrome(cell: cell)
        let line = ChromeLine(axis: .vertical, row: 1, column: 30, length: 3, color: grey, offset: 4)
        var bytes = ContiguousArray<UInt8>()
        chrome.render([line], into: &bytes)
        let controls = commands(bytes)
        #expect(controls.count == 2)
        #expect(controls[0] == "a=t,f=32,t=d,i=1048576,s=1,v=60,q=2")
        #expect(controls[1].hasPrefix("a=p,i=1048576,p="))
        #expect(controls[1].hasSuffix(",z=-1,X=4,C=1,q=2"))
        #expect(String(decoding: bytes, as: UTF8.self).contains("\u{1b}[2;31H"))
        let payload = String(decoding: bytes, as: UTF8.self).split(separator: ";")[1].prefix { $0 != "\u{1b}" }
        #expect(payload.count == 320)  // 60 RGBA pixels, base64

        var again = ContiguousArray<UInt8>()
        chrome.render([line], into: &again)
        #expect(again.isEmpty)
        #expect(chrome.isCurrent([line]))
    }

    @Test
    func `moving a line deletes the placements and reuses the image`() {
        var chrome = PixelChrome(cell: cell)
        var bytes = ContiguousArray<UInt8>()
        chrome.render([ChromeLine(axis: .horizontal, row: 0, column: 0, length: 8, color: grey)], into: &bytes)
        bytes.removeAll()
        chrome.render([ChromeLine(axis: .horizontal, row: 2, column: 0, length: 8, color: grey)], into: &bytes)
        let controls = commands(bytes)
        #expect(controls.first == "a=d,d=a,q=2")
        #expect(!controls.contains { $0.hasPrefix("a=t") })
        #expect(controls.last?.hasPrefix("a=p,i=1048576,p=") == true)
        #expect(String(decoding: bytes, as: UTF8.self).contains("\u{1b}[3;1H"))
    }

    @Test
    func `invalidation re-places without retransmitting and a reset transmits afresh`() {
        var chrome = PixelChrome(cell: cell)
        let line = ChromeLine(axis: .vertical, row: 0, column: 5, length: 2, color: grey)
        var bytes = ContiguousArray<UInt8>()
        chrome.render([line], into: &bytes)

        chrome.invalidate()
        bytes.removeAll()
        chrome.render([line], into: &bytes)
        #expect(commands(bytes).map { String($0.prefix(3)) } == ["a=d", "a=p"])
        #expect(commands(bytes)[0] == "a=d,d=a,q=2")

        chrome.reset()
        bytes.removeAll()
        chrome.render([line], into: &bytes)
        #expect(commands(bytes).map { String($0.prefix(3)) } == ["a=d", "a=t", "a=p"])
        #expect(commands(bytes)[0] == "a=d,d=A,q=2")
    }

    @Test
    func `an empty line set after lines deletes them and a zero-length line is skipped`() {
        var chrome = PixelChrome(cell: cell)
        var bytes = ContiguousArray<UInt8>()
        chrome.render([ChromeLine(axis: .vertical, row: 0, column: 0, length: 1, color: grey)], into: &bytes)
        bytes.removeAll()
        chrome.render([ChromeLine(axis: .vertical, row: 0, column: 0, length: 0, color: grey)], into: &bytes)
        #expect(commands(bytes) == ["a=d,d=a,q=2"])
    }

    @Test
    @MainActor
    func `the pipeline places chrome inside the frame and drops it on resize`() throws {
        let connection = MockTerminalConnection(size: TerminalSize(columns: 20, rows: 4))
        let pipeline = RenderPipeline(connection: connection, columns: 20, rows: 4)
        pipeline.chrome = PixelChrome(cell: cell)
        pipeline.chromeLines = [ChromeLine(axis: .vertical, row: 0, column: 10, length: 4, color: grey)]
        pipeline.beginFrame()
        pipeline.buffer.write("hi", row: 0, col: 0, style: .default)
        try pipeline.flush()
        let frame = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(frame.contains("\u{1b}_Ga=t,f=32,t=d,i=1048576,s=1,v=80,q=2;"))
        #expect(frame.contains("z=-1,C=1,q=2"))
        #expect(frame.hasSuffix("\u{1b}[?2026l"))

        connection.clearOutput()
        pipeline.beginFrame()
        try pipeline.flush()
        #expect(!String(decoding: connection.writtenOutput, as: UTF8.self).contains("\u{1b}_G"))

        pipeline.resize(columns: 20, rows: 4)
        connection.clearOutput()
        pipeline.beginFrame()
        try pipeline.flush()
        let redrawn = String(decoding: connection.writtenOutput, as: UTF8.self)
        #expect(redrawn.contains("\u{1b}_Ga=d,d=A,q=2"))
        #expect(redrawn.contains("\u{1b}_Ga=t,"))
    }
}
