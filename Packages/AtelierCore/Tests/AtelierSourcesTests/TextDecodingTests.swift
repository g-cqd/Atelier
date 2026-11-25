import Foundation
import Testing

@testable import AtelierSources

/// A file's text is its bytes decoded as UTF-8 in one pass, with the output the two-step decoding gave before.
struct TextDecodingTests {
    @Test
    func `a leading byte-order mark is dropped from a file's text`() {
        #expect(SourceLoader.text(from: Data([0xEF, 0xBB, 0xBF]) + Data("let a = 1\n".utf8)) == "let a = 1\n")
    }

    @Test
    func `a byte-order mark past the start is kept`() {
        #expect(SourceLoader.text(from: Data("a".utf8) + Data([0xEF, 0xBB, 0xBF]) + Data("b".utf8)) == "a\u{FEFF}b")
    }

    @Test
    func `bytes that are not UTF-8 decode one character per byte, so an edit stays visible`() {
        #expect(SourceLoader.text(from: Data([0x61, 0xFF, 0x62, 0xC0, 0xAF, 0x63])) == "a\u{FF}b\u{C0}\u{AF}c")
        #expect(SourceLoader.text(from: Data([0x63, 0x61, 0x66, 0xE9])) == "caf\u{E9}")
        #expect(SourceLoader.text(from: Data([0x63, 0x61, 0x66, 0xE8])) == "caf\u{E8}")
    }

    @Test(arguments: [String.Encoding.utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian])
    func `a UTF-16 or UTF-32 file with its byte-order mark reads as text`(encoding: String.Encoding) throws {
        let mark: [UInt8] =
            switch encoding {
                case .utf16LittleEndian: [0xFF, 0xFE]
                case .utf16BigEndian: [0xFE, 0xFF]
                case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
                default: [0x00, 0x00, 0xFE, 0xFF]
            }
        let data = Data(mark) + (try #require("let café = 1\n".data(using: encoding)))

        #expect(SourceLoader.text(from: data) == "let café = 1\n")
    }

    @Test
    func `a binary file's placeholder tells two versions of nearly the same size apart`() {
        let old = Data([0, 1, 2] + [UInt8](repeating: 7, count: 2_000))
        let new = Data([0, 1, 3] + [UInt8](repeating: 7, count: 2_000))

        #expect(SourceLoader.text(from: old).hasPrefix("(binary file, 2003 bytes, blob "))
        #expect(SourceLoader.text(from: old) != SourceLoader.text(from: new))
    }

    @Test
    func `valid text is decoded as it is`() {
        let text = "let café = \"naïve 日本語\"\n"
        #expect(SourceLoader.text(from: Data(text.utf8)) == text)
    }
}
