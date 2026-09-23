import Testing

@testable import KittyCodecs

/// The decoders' buffer caps: a sequence that never terminates ends as `.invalid`, and parsing resumes after it.
@Suite
struct DecoderOverflowGuardsTests {
    @Test
    func `KeyboardDecoder rejects a never-terminating CSI sequence longer than the cap`() {
        var decoder = KeyboardDecoder()
        // `ESC [ 1`, then 5_000 digits with no terminator, far past the cap.
        var lastResult: DecoderResult<KeyEvent> = .pending
        let prefix: [UInt8] = [0x1b, 0x5b, 0x31]  // ESC [ 1
        for byte in prefix {
            lastResult = decoder.feed(byte)
            #expect(lastResult == .pending)
        }
        var sawInvalid = false
        for _ in 0 ..< 5_000 {
            lastResult = decoder.feed(0x30)  // '0'
            if case .invalid = lastResult {
                sawInvalid = true
                break
            }
        }
        #expect(sawInvalid, "buffer cap must abort the sequence before 5_000 bytes")

        // After the abort, the decoder should be back in `.ground` and able
        // to parse a fresh keystroke.
        #expect(decoder.feed(0x61) == .complete(KeyEvent(keyCode: 97)))
    }

    @Test
    func `KeyboardDecoder rejects unbounded alternateKeys via repeated colon separators`() {
        var decoder = KeyboardDecoder()
        // ESC [ 1 : 1 : 1 : …, one alternate after another, never finishing the CSI u.
        let header: [UInt8] = [0x1b, 0x5b, 0x31]  // ESC [ 1
        for byte in header {
            #expect(decoder.feed(byte) == .pending)
        }
        var sawInvalid = false
        for _ in 0 ..< 1_000 {
            let colon = decoder.feed(0x3a)  // ':'
            if case .invalid = colon {
                sawInvalid = true
                break
            }
            let digit = decoder.feed(0x31)  // '1'
            if case .invalid = digit {
                sawInvalid = true
                break
            }
        }
        #expect(sawInvalid, "alternateKeys cap must abort before 1_000 separators")
        #expect(decoder.feed(0x61) == .complete(KeyEvent(keyCode: 97)))
    }

    @Test
    func `KeyboardDecoder rejects unbounded textCodepoints via repeated colon separators`() {
        var decoder = KeyboardDecoder()
        // ESC [ 1 ; 1 ; 1 (now in textCodepoints state with currentTextCP = 1)
        // then a stream of `:1` pairs.
        let header: [UInt8] = [
            0x1b, 0x5b,  // ESC [
            0x31,  // 1 (keyCode)
            0x3b,  // ; (start modifiers)
            0x31,  // 1
            0x3b,  // ; (start textCodepoints)
            0x31  // 1 (first codepoint)
        ]
        for byte in header {
            #expect(decoder.feed(byte) == .pending)
        }
        var sawInvalid = false
        for _ in 0 ..< 2_000 {
            let colon = decoder.feed(0x3a)
            if case .invalid = colon {
                sawInvalid = true
                break
            }
            let digit = decoder.feed(0x31)
            if case .invalid = digit {
                sawInvalid = true
                break
            }
        }
        #expect(sawInvalid, "textCodepoints cap must abort before 2_000 separators")
        #expect(decoder.feed(0x61) == .complete(KeyEvent(keyCode: 97)))
    }

    @Test
    func `MouseDecoder rejects a never-terminating sequence longer than the cap`() {
        var decoder = MouseDecoder()
        var sawInvalid = false
        for byte: UInt8 in [0x1b, 0x5b, 0x3c] {  // ESC [ <
            _ = decoder.feed(byte)
        }
        // Zeros keep the button value at 0, so only the buffer cap can end the sequence.
        for _ in 0 ..< 500 {
            let r = decoder.feed(0x30)  // '0'
            if case .invalid = r {
                sawInvalid = true
            }
        }
        #expect(sawInvalid)
        // A valid sequence after the overflow must not crash the decoder; nothing more is asserted.
        for byte: UInt8 in [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x3b, 0x31, 0x4d] {
            _ = decoder.feed(byte)
        }
    }
}
