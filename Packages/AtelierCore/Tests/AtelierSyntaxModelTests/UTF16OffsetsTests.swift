import Testing

@testable import AtelierSyntaxModel

struct UTF16OffsetsTests {
    @Test
    func `a walk in steps counts the utf16 length of the text before each stop`() {
        let characters = ["a", " ", "é", "✓", "変", "🙂", "𝔘", "\r\n"]
        var random = SplitMix64(seed: 0x10)
        for _ in 0 ..< 500 {
            let text = (0 ..< Int(random.next() % 48)).map { _ in characters[Int(random.next() % 8)] }.joined()
            let bytes = Array(text.utf8)
            var stops: [Int] = [0]
            for character in text { stops.append(stops[stops.count - 1] + character.utf8.count) }
            var byte = 0
            var unit = 0
            var stop = 0
            while stop < stops.count - 1 {
                stop = min(stop + 1 + Int(random.next() % 12), stops.count - 1)
                UTF16Offsets.advance(&byte, to: stops[stop], in: bytes.span, counting: &unit)
                #expect(byte == stops[stop])
                #expect(unit == String(decoding: bytes[..<stops[stop]], as: UTF8.self).utf16.count, "\(text)")
            }
        }
    }

    @Test
    func `the first non ASCII byte is found past eight byte words and in the tail`() {
        let text = Array("abcdefghijklmnopqrs é".utf8)
        #expect(UTF16Offsets.firstNonASCII(in: text.span, from: 0) == 20)
        #expect(UTF16Offsets.firstNonASCII(in: text.span, from: 20) == 20)
        #expect(UTF16Offsets.firstNonASCII(in: text.span, from: 22) == 22)
        let ascii = Array("abcdefghijk".utf8)
        #expect(UTF16Offsets.firstNonASCII(in: ascii.span, from: 1) == ascii.count)
        for offset in 0 ..< 17 {
            var bytes = [UInt8](repeating: UInt8(ascii: "x"), count: 17)
            bytes[offset] = 0xC3
            #expect(UTF16Offsets.firstNonASCII(in: bytes.span, from: 0) == offset)
        }
    }
}
