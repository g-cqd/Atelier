import Foundation
import Testing

@testable import AtelierSources

/// Which bytes make a file binary: a NUL among them, not only among the first 8 KiB. A file with a NUL anywhere is no
/// text a diff can show, whatever its first lines look like.
struct BinaryDetectionTests {
    /// `count` bytes of "a" with a NUL at `offset`, when it is below `count`.
    private static func bytes(count: Int, nulAt offset: Int? = nil) -> Data {
        var data = Data(repeating: UInt8(ascii: "a"), count: count)
        if let offset { data[offset] = 0 }
        return data
    }

    @Test
    func `a NUL past the first 8 KiB makes the file binary`() {
        let text = SourceLoader.text(from: Self.bytes(count: 20_000, nulAt: 10_000))
        let isPlaceholder = text.hasPrefix("(binary file, ")
        #expect(isPlaceholder, "the file loaded as \(text.utf8.count) bytes of text")
        let keepsNUL = text.utf8.contains(0)
        #expect(!keepsNUL, "the NUL reached the text")
    }

    /// Passes today and after the fix: the last byte the current check reads.
    @Test
    func `a NUL in the last of the first 8 KiB makes the file binary`() {
        let text = SourceLoader.text(from: Self.bytes(count: 20_000, nulAt: 8_191))
        let isPlaceholder = text.hasPrefix("(binary file, ")
        #expect(isPlaceholder)
    }

    /// Passes today and after the fix: a wider scan must not turn a big text file into a binary one.
    @Test
    func `a large file without a NUL loads whole as text`() {
        let data = Self.bytes(count: 1 << 20)
        let textSize = SourceLoader.text(from: data).utf8.count
        #expect(textSize == data.count)
    }
}
