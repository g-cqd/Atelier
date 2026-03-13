import Testing

@testable import KittyCodecs

@Suite
struct KeyboardDecoderExtendedTests {
    @Test
    func `CSI u with text codepoints field decodes keyCode and associatedText`() throws {
        var decoder = KeyboardDecoder()
        // ESC [ 97 ; 1 ; 65 u  →  keyCode=97, modifiers=[] (1-1=0), text='A' (65)
        // Bytes: 0x1b 0x5b 0x39 0x37 0x3b 0x31 0x3b 0x36 0x35 0x75
        for byte: UInt8 in [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x31, 0x3b, 0x36, 0x35] {
            #expect(decoder.feed(byte) == .pending)
        }
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75))
        #expect(event.keyCode == 97)
        #expect(event.associatedText == "A")
    }

    @Test
    func `empty CSI u produces keyCode zero with empty modifiers and associatedText`() throws {
        var decoder = KeyboardDecoder()
        // ESC [ u  →  keyCode=0, no modifiers, no text
        #expect(decoder.feed(0x1b) == .pending)
        #expect(decoder.feed(0x5b) == .pending)
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75))
        #expect(event.keyCode == 0)
        #expect(event.modifiers == [])
        #expect(event.associatedText == "")
    }

    @Test
    func `CSI u text codepoints preserve combining scalar sequences`() throws {
        var decoder = KeyboardDecoder()
        let bytes = Array("\u{1B}[101;1;101:769u".utf8)

        for byte in bytes.dropLast() {
            #expect(decoder.feed(byte) == .pending)
        }

        let event = try requireCompletedKeyboardEvent(decoder.feed(bytes.last!))
        #expect(event.keyCode == 101)
        #expect(event.associatedText == "e\u{301}")
    }
}
