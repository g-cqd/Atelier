import Testing

@testable import KittyCodecs

@Suite
struct KeyboardDecoderTests {
    @Test
    func `Plain ASCII character`() throws {
        var decoder = KeyboardDecoder()
        let result = decoder.feed(0x61)  // 'a'
        let event = try requireCompletedKeyboardEvent(result)
        #expect(event.keyCode == 97)
        #expect(event.modifiers == [])
    }

    @Test
    func `CSI u simple key`() throws {
        var decoder = KeyboardDecoder()
        // ESC [ 97 u → 'a'
        #expect(decoder.feed(0x1b) == .pending)
        #expect(decoder.feed(0x5b) == .pending)
        #expect(decoder.feed(0x39) == .pending)  // 9
        #expect(decoder.feed(0x37) == .pending)  // 7
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75))  // u
        #expect(event.keyCode == 97)  // 'a'
    }

    @Test
    func `CSI u with modifiers`() throws {
        var decoder = KeyboardDecoder()
        // ESC [ 97 ; 2 u → 'a' with shift (modifiers = 2, meaning shift since 2-1=1)
        for byte: UInt8 in [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x32] {
            _ = decoder.feed(byte)
        }
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75))
        #expect(event.keyCode == 97)
        #expect(event.modifiers == .shift)
    }

    @Test
    func `CSI u with event type`() throws {
        var decoder = KeyboardDecoder()
        // ESC [ 97 ; 1 : 3 u → 'a' with no modifiers, release event
        for byte in [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x31, 0x3a, 0x33] as [UInt8] {
            _ = decoder.feed(byte)
        }
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75))
        #expect(event.keyCode == 97)
        #expect(event.eventType == .release)
    }

    @Test
    func `ESC plus char produces Alt modifier`() throws {
        var decoder = KeyboardDecoder()
        _ = decoder.feed(0x1b)  // ESC
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x61))  // 'a'
        #expect(event.modifiers == .alt)
    }

    @Test(arguments: [
        ("\u{1B}[42949672960u", "\u{1B}[4294967296"),
        ("\u{1B}[1:42949672960u", "\u{1B}[1:4294967296"),
        ("\u{1B}[1;256u", "\u{1B}[1;256"),
        ("\u{1B}[1;1:256u", "\u{1B}[1;1:256"),
        ("\u{1B}[1;1;42949672960u", "\u{1B}[1;1;4294967296")
    ])
    func `Numeric overflow returns invalid`(sequence: String, invalidPrefix: String) {
        var decoder = KeyboardDecoder()
        #expect(feedKeyboard(sequence, into: &decoder) == .invalid(Array(invalidPrefix.utf8)))
        #expect(decoder.feed(0x61) == .complete(KeyEvent(keyCode: 97)))
    }
}
