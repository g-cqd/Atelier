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
    func `an invalid sequence becomes a replacement character`() {
        #expect(SourceLoader.text(from: Data([0x61, 0xFF, 0x62, 0xC0, 0xAF, 0x63])) == "a\u{FFFD}b\u{FFFD}\u{FFFD}c")
    }

    @Test
    func `valid text is decoded as it is`() {
        let text = "let café = \"naïve 日本語\"\n"
        #expect(SourceLoader.text(from: Data(text.utf8)) == text)
    }
}
