import Testing

@testable import KittyCodecs

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
        #expect(bytes.contains(0x34))  // 4
        #expect(bytes.contains(0x3a))  // :
        #expect(bytes.contains(0x33))  // 3
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
