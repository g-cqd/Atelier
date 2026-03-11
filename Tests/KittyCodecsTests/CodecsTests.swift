import Testing
@testable import KittyCodecs

@Suite
struct StyleAndColorTypesTests {
    @Test
    func `Default style equality`() {
        #expect(Style.default == Style())
    }

    @Test
    func `Color equality`() {
        #expect(Color.rgb(r: 255, g: 0, b: 0) == Color.rgb(r: 255, g: 0, b: 0))
        #expect(Color.indexed(1) != Color.indexed(2))
    }

    @Test
    func `KeyModifiers option set`() {
        var mods: KeyModifiers = [.shift, .ctrl]
        #expect(mods.contains(.shift))
        #expect(mods.contains(.ctrl))
        #expect(!mods.contains(.alt))
        mods.insert(.alt)
        #expect(mods.contains(.alt))
    }
}

@Suite
struct SGREncoderTests {
    @Test
    func `Default style produces empty bytes`() {
        #expect(SGREncoder.encode(.default) == [])
    }

    @Test
    func `Bold style`() {
        let style = Style(bold: true)
        let bytes = SGREncoder.encode(style)
        // ESC [ 1 m
        #expect(bytes == [0x1b, 0x5b, 0x31, 0x6d])
    }

    @Test
    func `RGB foreground color`() {
        let style = Style(fg: .rgb(r: 255, g: 128, b: 0))
        let bytes = SGREncoder.encode(style)
        let expected: [UInt8] = [0x1b, 0x5b] + "38;2;255;128;0".utf8 + [0x6d]
        #expect(bytes == expected)
    }

    @Test
    func `Diff encoding no change produces empty`() {
        let style = Style(bold: true, italic: true)
        #expect(SGREncoder.encodeDiff(from: style, to: style) == [])
    }

    @Test
    func `Diff encoding reset to default`() {
        let old = Style(bold: true)
        #expect(SGREncoder.encodeDiff(from: old, to: .default) == [0x1b, 0x5b, 0x6d])
    }

    @Test
    func `Styled underline encoding`() {
        let style = Style(underline: .curly)
        let bytes = SGREncoder.encode(style)
        // Should contain 4:3 (curly underline)
        #expect(bytes.contains(0x34)) // 4
        #expect(bytes.contains(0x3a)) // :
        #expect(bytes.contains(0x33)) // 3
    }

    @Test
    func `Indexed color < 8`() {
        let style = Style(fg: .indexed(1))
        let bytes = SGREncoder.encode(style)
        // Should use 31 (red)
        let expected: [UInt8] = [0x1b, 0x5b] + "31".utf8 + [0x6d]
        #expect(bytes == expected)
    }

    @Test
    func `Indexed color >= 16`() {
        let style = Style(fg: .indexed(200))
        let bytes = SGREncoder.encode(style)
        let expected: [UInt8] = [0x1b, 0x5b] + "38;5;200".utf8 + [0x6d]
        #expect(bytes == expected)
    }

    @Test
    func `Diff encoding resets underline color`() {
        let old = Style(underlineColor: .rgb(r: 255, g: 0, b: 0), bold: true)
        let new = Style(bold: true)
        let expected: [UInt8] = [0x1b, 0x5b] + "59".utf8 + [0x6d]
        #expect(SGREncoder.encodeDiff(from: old, to: new) == expected)
    }

    @Test
    func `Diff encoding reapplies bold after clearing dim`() {
        let old = Style(dim: true)
        let new = Style(bold: true)
        let expected: [UInt8] = [0x1b, 0x5b] + "22;1".utf8 + [0x6d]
        #expect(SGREncoder.encodeDiff(from: old, to: new) == expected)
    }

    @Test
    func `Diff encoding reapplies dim after clearing bold`() {
        let old = Style(bold: true)
        let new = Style(dim: true)
        let expected: [UInt8] = [0x1b, 0x5b] + "22;2".utf8 + [0x6d]
        #expect(SGREncoder.encodeDiff(from: old, to: new) == expected)
    }
}

@Suite
struct KeyboardDecoderTests {
    @Test
    func `Plain ASCII character`() throws {
        var decoder = KeyboardDecoder()
        let result = decoder.feed(0x61) // 'a'
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
        #expect(decoder.feed(0x39) == .pending) // 9
        #expect(decoder.feed(0x37) == .pending) // 7
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x75)) // u
        #expect(event.keyCode == 97) // 'a'
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
        _ = decoder.feed(0x1b) // ESC
        let event = try requireCompletedKeyboardEvent(decoder.feed(0x61)) // 'a'
        #expect(event.modifiers == .alt)
    }

    @Test( arguments: [        ("\u{1B}[42949672960u", "\u{1B}[4294967296"),
        ("\u{1B}[1:42949672960u", "\u{1B}[1:4294967296"),
        ("\u{1B}[1;256u", "\u{1B}[1;256"),
        ("\u{1B}[1;1:256u", "\u{1B}[1;1:256"),
        ("\u{1B}[1;1;42949672960u", "\u{1B}[1;1;4294967296"),
    ])
    func `Numeric overflow returns invalid`(sequence: String, invalidPrefix: String) {
        var decoder = KeyboardDecoder()
        #expect(feedKeyboard(sequence, into: &decoder) == .invalid(Array(invalidPrefix.utf8)))
        #expect(decoder.feed(0x61) == .complete(KeyEvent(keyCode: 97)))
    }
}

@Suite
struct MouseDecoderTests {
    @Test
    func `Left click at row 5 col 10`() throws {
        var decoder = MouseDecoder()
        // ESC [ < 0 ; 10 ; 5 M
        for byte in [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35] as [UInt8] {
            _ = decoder.feed(byte)
        }
        let event = try requireCompletedMouseEvent(decoder.feed(0x4d)) // M
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
        let event = try requireCompletedMouseEvent(decoder.feed(0x6d)) // m
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

    @Test( arguments: [        ("\u{1B}[<65536;1;1M", "\u{1B}[<65536"),
        ("\u{1B}[<0;65536;1M", "\u{1B}[<0;65536"),
        ("\u{1B}[<0;1;65536M", "\u{1B}[<0;1;65536"),
    ])
    func `Numeric overflow returns invalid`(sequence: String, invalidPrefix: String) {
        var decoder = MouseDecoder()
        #expect(feedMouse(sequence, into: &decoder) == .invalid(Array(invalidPrefix.utf8)))
        #expect(decoder.feed(0x1b) == .pending)
    }

    @Test( arguments: [        ("\u{1B}[<128;1;1M", MouseButton.button4),
        ("\u{1B}[<129;1;1M", MouseButton.button5),
    ])
    func `Extra buttons decode from high values`(sequence: String, expectedButton: MouseButton) throws {
        var decoder = MouseDecoder()
        let event = try requireCompletedMouseEvent(feedMouse(sequence, into: &decoder))
        #expect(event.button == expectedButton)
        #expect(event.kind == .press)
    }
}

@Suite
struct KittySequencesTests {
    @Test
    func `Sync output markers`() {
        // CSI ? 2026 h
        #expect(KittySequences.beginSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x68])
        #expect(KittySequences.endSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c])
    }

    @Test
    func `Push keyboard mode`() {
        let bytes = KittySequences.pushKeyboardMode(flags: 31)
        // CSI > 31 u
        #expect(bytes == [0x1b, 0x5b, 0x3e, 0x33, 0x31, 0x75])
    }

    @Test
    func `Move cursor`() {
        let bytes = KittySequences.moveCursor(row: 5, col: 10)
        // CSI 5 ; 10 H
        #expect(bytes == [0x1b, 0x5b, 0x35, 0x3b, 0x31, 0x30, 0x48])
    }

    @Test( arguments: [        (-5, 0, "\u{1B}[1;1H"),
        (65_535, 65_535, "\u{1B}[65535;65535H"),
        (70_000, 80_000, "\u{1B}[65535;65535H"),
    ])
    func `Move cursor clamps edge values`(row: Int, col: Int, expectedSequence: String) {
        #expect(KittySequences.moveCursor(row: row, col: col) == Array(expectedSequence.utf8))
    }
}

// MARK: - GraphicsEncoder Tests

@Suite
struct GraphicsEncoderTests {
    @Test
    func `Small payload fits in single chunk`() {
        let cmd = GraphicsCommand(
            action: .transmitAndDisplay,
            format: .png,
            transmission: .direct,
            payload: [0x89, 0x50, 0x4E, 0x47] // PNG magic bytes
        )
        let bytes = GraphicsEncoder.encode(cmd)
        // Should contain APC start (ESC _), 'G', control params, ';', base64 payload, ST (ESC \)
        #expect(bytes.first == 0x1b)
        #expect(bytes[1] == 0x5f) // _ (APC)
        #expect(bytes[2] == 0x47) // G
        // Should end with ESC \ (ST)
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
        // Should NOT contain m=1 (no continuation)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(!asString.contains("m=1"))
    }

    @Test
    func `Control part includes action format transmission`() {
        let cmd = GraphicsCommand(
            action: .query,
            format: .rgb,
            transmission: .file,
            payload: [1, 2, 3]
        )
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(asString.contains("a=q"))
        #expect(asString.contains("f=24"))
        #expect(asString.contains("t=f"))
    }

    @Test
    func `Control includes id width height when nonzero`() {
        let cmd = GraphicsCommand(
            action: .transmitAndDisplay,
            format: .rgba,
            transmission: .direct,
            id: 42,
            width: 100,
            height: 50,
            payload: [0xFF]
        )
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(asString.contains("i=42"))
        #expect(asString.contains("s=100"))
        #expect(asString.contains("v=50"))
    }

    @Test
    func `Control omits id width height when zero`() {
        let cmd = GraphicsCommand(payload: [0xFF])
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(!asString.contains("i="))
        #expect(!asString.contains("s="))
        #expect(!asString.contains("v="))
    }

    @Test
    func `Large payload produces multiple chunks with m=1 continuation`() {
        // Create a payload that will exceed 4096 bytes when base64-encoded
        // Base64 expands 3 bytes to 4 chars, so 3073 bytes → 4100 chars (> 4096)
        let cmd = GraphicsCommand(payload: Array(repeating: 0xAB, count: 3073))
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        // Should contain m=1 for continuation
        #expect(asString.contains("m=1"))
        // Should contain multiple APC sequences (multiple ESC _ G ... ESC \)
        let apcCount = asString.components(separatedBy: "\u{1B}_G").count - 1
        #expect(apcCount >= 2)
    }

    @Test
    func `Empty payload produces valid single chunk`() {
        let cmd = GraphicsCommand(payload: [])
        let bytes = GraphicsEncoder.encode(cmd)
        #expect(bytes.first == 0x1b)
        #expect(bytes.last == 0x5c)
    }
}

// MARK: - Clipboard Tests

@Suite
struct ClipboardTests {
    @Test
    func `setClipboard produces OSC 52 sequence`() {
        let bytes = KittySequences.setClipboard("SGVsbG8=") // "Hello" in base64
        // OSC 52 ; c ; <base64> ST
        #expect(bytes[0] == 0x1b)
        #expect(bytes[1] == 0x5d) // ] (OSC)
        let body = String(bytes: Array(bytes[2 ..< bytes.count - 2]), encoding: .utf8) ?? ""
        #expect(body == "52;c;SGVsbG8=")
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
    }

    @Test
    func `requestClipboard produces OSC 52 query`() {
        let bytes = KittySequences.requestClipboard
        let expected: [UInt8] = [0x1b, 0x5d] + "52;c;?".utf8 + [0x1b, 0x5c]
        #expect(bytes == expected)
    }

    @Test
    func `setClipboard with empty string produces valid sequence`() {
        let bytes = KittySequences.setClipboard("")
        let expected: [UInt8] = [0x1b, 0x5d] + "52;c;".utf8 + [0x1b, 0x5c]
        #expect(bytes == expected)
    }
}

// MARK: - Notification Tests

@Suite
struct NotificationsTests {
    @Test
    func `notify with title only produces single OSC 99 sequence`() {
        let bytes = KittySequences.notify(title: "Build done")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(asString.contains("99;i=1:d=0:p=title;Build done"))
        // Should not have body part
        #expect(!asString.contains("p=body"))
        // Single ST at end
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
    }

    @Test
    func `notify with title and body produces two OSC 99 sequences`() {
        let bytes = KittySequences.notify(title: "Alert", body: "Check logs")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(asString.contains("p=title;Alert"))
        #expect(asString.contains("p=body;Check logs"))
    }

    @Test
    func `notify with empty body produces title-only sequence`() {
        let bytes = KittySequences.notify(title: "Test", body: "")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(!asString.contains("p=body"))
    }
}

// MARK: - Helpers

private func feedKeyboard(_ sequence: String, into decoder: inout KeyboardDecoder) -> DecoderResult<KeyEvent> {
    var result: DecoderResult<KeyEvent> = .pending
    for byte in sequence.utf8 {
        result = decoder.feed(byte)
        switch result {
        case .pending:
            continue
        case .complete, .invalid:
            return result
        }
    }
    return result
}

private func feedMouse(_ sequence: String, into decoder: inout MouseDecoder) -> DecoderResult<MouseEvent> {
    var result: DecoderResult<MouseEvent> = .pending
    for byte in sequence.utf8 {
        result = decoder.feed(byte)
        switch result {
        case .pending:
            continue
        case .complete, .invalid:
            return result
        }
    }
    return result
}

private enum DecoderExpectationError: Error {
    case expectedCompleteKeyboardEvent
    case expectedCompleteMouseEvent
}

private func requireCompletedKeyboardEvent(_ result: DecoderResult<KeyEvent>) throws -> KeyEvent {
    guard case let .complete(event) = result else {
        throw DecoderExpectationError.expectedCompleteKeyboardEvent
    }
    return event
}

private func requireCompletedMouseEvent(_ result: DecoderResult<MouseEvent>) throws -> MouseEvent {
    guard case let .complete(event) = result else {
        throw DecoderExpectationError.expectedCompleteMouseEvent
    }
    return event
}
