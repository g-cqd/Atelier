import Testing

@testable import AtelierParser

/// How the lexer reads scalars out of UTF-8, one malformed byte at a time as U+FFFD.
@Suite
struct TokenScannerDecodeTests {
    @Test
    func `A well-formed scalar reads whole`() {
        #expect(Self.decode([0xC3, 0xA9]) == Decoded(scalar: 0xE9, length: 2))
        #expect(Self.decode([0xF0, 0x9F, 0x98, 0x80]) == Decoded(scalar: 0x1F600, length: 4))
    }

    @Test(arguments: [[0xE2, 0x41, 0x41], [0xE2, 0x82], [0xF8, 0x80, 0x80, 0x80], [0x80]] as [[UInt8]])
    func `A malformed sequence reads as one replacement byte`(bytes: [UInt8]) {
        #expect(Self.decode(bytes) == Decoded(scalar: 0xFFFD, length: 1))
    }

    private struct Decoded: Equatable {
        var scalar: UInt32
        var length: Int
    }

    private static func decode(_ bytes: [UInt8]) -> Decoded {
        bytes.withUnsafeBufferPointer { buffer in
            let (scalar, length) = TokenScanner.decode(buffer, at: 0)
            return Decoded(scalar: scalar, length: length)
        }
    }
}
