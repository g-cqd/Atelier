import Testing

@testable import KittyCodecs

@Suite
struct MouseDecoderTests {
    @Test
    func `Left click at row 5 col 10`() throws {
        var decoder = MouseDecoder()
        // ESC [ < 0 ; 10 ; 5 M
        for byte in [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35] as [UInt8] {
            _ = decoder.feed(byte)
        }
        let event = try requireCompletedMouseEvent(decoder.feed(0x4d))  // M
        #expect(event.button == .left)
        #expect(event.kind == .press)
        #expect(event.col == 10)
        #expect(event.row == 5)
    }

    @Test
    func `Right click release`() throws {
        var decoder = MouseDecoder()
        // ESC [ < 2 ; 1 ; 1 m
        for byte in [0x1b, 0x5b, 0x3c, 0x32, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        let event = try requireCompletedMouseEvent(decoder.feed(0x6d))  // m
        #expect(event.button == .right)
        #expect(event.kind == .release)
    }

    @Test
    func `Scroll up`() throws {
        var decoder = MouseDecoder()
        // ESC [ < 64 ; 1 ; 1 M
        for byte in [0x1b, 0x5b, 0x3c, 0x36, 0x34, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        #expect(try requireCompletedMouseEvent(decoder.feed(0x4d)).button == .scrollUp)
    }

    @Test
    func `Shift modifier in mouse event`() throws {
        var decoder = MouseDecoder()
        // ESC [ < 4 ; 1 ; 1 M (button bits: 4 = shift + left)
        for byte in [0x1b, 0x5b, 0x3c, 0x34, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        #expect(try requireCompletedMouseEvent(decoder.feed(0x4d)).modifiers.contains(.shift))
    }

    @Test(arguments: [
        ("\u{1B}[<65536;1;1M", "\u{1B}[<65536"),
        ("\u{1B}[<0;65536;1M", "\u{1B}[<0;65536"),
        ("\u{1B}[<0;1;65536M", "\u{1B}[<0;1;65536")
    ])
    func `Numeric overflow returns invalid`(sequence: String, invalidPrefix: String) {
        var decoder = MouseDecoder()
        #expect(feedMouse(sequence, into: &decoder) == .invalid(Array(invalidPrefix.utf8)))
        #expect(decoder.feed(0x1b) == .pending)
    }

    @Test(arguments: [
        ("\u{1B}[<128;1;1M", MouseButton.button4),
        ("\u{1B}[<129;1;1M", MouseButton.button5)
    ])
    func `Extra buttons decode from high values`(sequence: String, expectedButton: MouseButton)
        throws
    {
        var decoder = MouseDecoder()
        let event = try requireCompletedMouseEvent(feedMouse(sequence, into: &decoder))
        #expect(event.button == expectedButton)
        #expect(event.kind == .press)
    }
}
