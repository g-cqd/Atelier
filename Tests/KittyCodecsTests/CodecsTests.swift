import Testing
@testable import KittyCodecs

@Suite("Style & Color Types")
struct TypesTests {
    @Test("Default style equality")
    func defaultStyle() {
        #expect(Style.default == Style())
    }

    @Test("Color equality")
    func colorEquality() {
        #expect(Color.rgb(r: 255, g: 0, b: 0) == Color.rgb(r: 255, g: 0, b: 0))
        #expect(Color.indexed(1) != Color.indexed(2))
    }

    @Test("KeyModifiers option set")
    func keyModifiers() {
        var mods: KeyModifiers = [.shift, .ctrl]
        #expect(mods.contains(.shift))
        #expect(mods.contains(.ctrl))
        #expect(!mods.contains(.alt))
        mods.insert(.alt)
        #expect(mods.contains(.alt))
    }
}

@Suite("SGREncoder")
struct SGREncoderTests {
    @Test("Default style produces empty bytes")
    func defaultStyleEmpty() {
        #expect(SGREncoder.encode(.default) == [])
    }

    @Test("Bold style")
    func boldStyle() {
        let style = Style(bold: true)
        let bytes = SGREncoder.encode(style)
        // ESC [ 1 m
        #expect(bytes == [0x1b, 0x5b, 0x31, 0x6d])
    }

    @Test("RGB foreground color")
    func rgbForeground() {
        let style = Style(fg: .rgb(r: 255, g: 128, b: 0))
        let bytes = SGREncoder.encode(style)
        let expected: [UInt8] = [0x1b, 0x5b] + "38;2;255;128;0".utf8 + [0x6d]
        #expect(bytes == expected)
    }

    @Test("Diff encoding — no change produces empty")
    func diffNoChange() {
        let style = Style(bold: true, italic: true)
        #expect(SGREncoder.encodeDiff(from: style, to: style) == [])
    }

    @Test("Diff encoding — reset to default")
    func diffToDefault() {
        let old = Style(bold: true)
        #expect(SGREncoder.encodeDiff(from: old, to: .default) == [0x1b, 0x5b, 0x6d])
    }

    @Test("Styled underline encoding")
    func styledUnderline() {
        let style = Style(underline: .curly)
        let bytes = SGREncoder.encode(style)
        // Should contain 4:3 (curly underline)
        #expect(bytes.contains(0x34)) // 4
        #expect(bytes.contains(0x3a)) // :
        #expect(bytes.contains(0x33)) // 3
    }

    @Test("Indexed color < 8")
    func indexedColorLow() {
        let style = Style(fg: .indexed(1))
        let bytes = SGREncoder.encode(style)
        // Should use 31 (red)
        let expected: [UInt8] = [0x1b, 0x5b] + "31".utf8 + [0x6d]
        #expect(bytes == expected)
    }

    @Test("Indexed color >= 16")
    func indexedColorHigh() {
        let style = Style(fg: .indexed(200))
        let bytes = SGREncoder.encode(style)
        let expected: [UInt8] = [0x1b, 0x5b] + "38;5;200".utf8 + [0x6d]
        #expect(bytes == expected)
    }
}

@Suite("KeyboardDecoder")
struct KeyboardDecoderTests {
    @Test("Plain ASCII character")
    func plainChar() {
        var decoder = KeyboardDecoder()
        let result = decoder.feed(0x61) // 'a'
        if case .complete(let event) = result {
            #expect(event.keyCode == 97)
            #expect(event.modifiers == [])
        } else {
            Issue.record("Expected complete event")
        }
    }

    @Test("CSI u simple key")
    func csiUSimple() {
        var decoder = KeyboardDecoder()
        // ESC [ 97 u → 'a'
        #expect(decoder.feed(0x1b) == .pending)
        #expect(decoder.feed(0x5b) == .pending)
        #expect(decoder.feed(0x39) == .pending) // 9
        #expect(decoder.feed(0x37) == .pending) // 7
        if case .complete(let event) = decoder.feed(0x75) { // u
            #expect(event.keyCode == 97) // 'a'
        } else {
            Issue.record("Expected complete event")
        }
    }

    @Test("CSI u with modifiers")
    func csiUModifiers() {
        var decoder = KeyboardDecoder()
        // ESC [ 97 ; 2 u → 'a' with shift (modifiers = 2, meaning shift since 2-1=1)
        for byte: UInt8 in [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x32] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x75) {
            #expect(event.keyCode == 97)
            #expect(event.modifiers == .shift)
        } else {
            Issue.record("Expected complete event")
        }
    }

    @Test("CSI u with event type")
    func csiUEventType() {
        var decoder = KeyboardDecoder()
        // ESC [ 97 ; 1 : 3 u → 'a' with no modifiers, release event
        for byte in [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x31, 0x3a, 0x33] as [UInt8] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x75) {
            #expect(event.keyCode == 97)
            #expect(event.eventType == .release)
        } else {
            Issue.record("Expected complete event")
        }
    }

    @Test("ESC + char produces Alt modifier")
    func escChar() {
        var decoder = KeyboardDecoder()
        _ = decoder.feed(0x1b) // ESC
        if case .complete(let event) = decoder.feed(0x61) { // 'a'
            #expect(event.modifiers == .alt)
        } else {
            Issue.record("Expected Alt+a")
        }
    }
}

@Suite("MouseDecoder")
struct MouseDecoderTests {
    @Test("Left click at row 5, col 10")
    func leftClick() {
        var decoder = MouseDecoder()
        // ESC [ < 0 ; 10 ; 5 M
        for byte in [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35] as [UInt8] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x4d) { // M
            #expect(event.button == .left)
            #expect(event.kind == .press)
            #expect(event.col == 10)
            #expect(event.row == 5)
        } else {
            Issue.record("Expected mouse event")
        }
    }

    @Test("Right click release")
    func rightRelease() {
        var decoder = MouseDecoder()
        // ESC [ < 2 ; 1 ; 1 m
        for byte in [0x1b, 0x5b, 0x3c, 0x32, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x6d) { // m
            #expect(event.button == .right)
            #expect(event.kind == .release)
        } else {
            Issue.record("Expected mouse release")
        }
    }

    @Test("Scroll up")
    func scrollUp() {
        var decoder = MouseDecoder()
        // ESC [ < 64 ; 1 ; 1 M
        for byte in [0x1b, 0x5b, 0x3c, 0x36, 0x34, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x4d) {
            #expect(event.button == .scrollUp)
        } else {
            Issue.record("Expected scroll event")
        }
    }

    @Test("Shift modifier in mouse event")
    func shiftMouse() {
        var decoder = MouseDecoder()
        // ESC [ < 4 ; 1 ; 1 M (button bits: 4 = shift + left)
        for byte in [0x1b, 0x5b, 0x3c, 0x34, 0x3b, 0x31, 0x3b, 0x31] as [UInt8] {
            _ = decoder.feed(byte)
        }
        if case .complete(let event) = decoder.feed(0x4d) {
            #expect(event.modifiers.contains(.shift))
        } else {
            Issue.record("Expected shifted mouse event")
        }
    }
}

@Suite("KittySequences")
struct KittySequencesTests {
    @Test("Sync output markers")
    func syncOutput() {
        // CSI ? 2026 h
        #expect(KittySequences.beginSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x68])
        #expect(KittySequences.endSyncUpdate == [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c])
    }

    @Test("Push keyboard mode")
    func pushKeyboard() {
        let bytes = KittySequences.pushKeyboardMode(flags: 31)
        // CSI > 31 u
        #expect(bytes == [0x1b, 0x5b, 0x3e, 0x33, 0x31, 0x75])
    }

    @Test("Move cursor")
    func moveCursor() {
        let bytes = KittySequences.moveCursor(row: 5, col: 10)
        // CSI 5 ; 10 H
        #expect(bytes == [0x1b, 0x5b, 0x35, 0x3b, 0x31, 0x30, 0x48])
    }
}
