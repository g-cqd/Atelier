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

    /// The offsets straddle the old 8 KiB window: its last byte, the first byte past it, and the last byte of the file.
    @Test(arguments: [8_191, 8_192, 19_999])
    func `a NUL at the offset makes the file binary`(offset: Int) {
        let text = SourceLoader.text(from: Self.bytes(count: 20_000, nulAt: offset))
        let isPlaceholder = text.hasPrefix("(binary file, ")
        #expect(isPlaceholder, "the file loaded as \(text.utf8.count) bytes of text")
        let keepsNUL = text.utf8.contains(0)
        #expect(!keepsNUL, "the NUL reached the text")
    }

    /// A whole-file scan must not turn a big text file into a binary one.
    @Test
    func `a large file without a NUL loads whole as text`() {
        let data = Self.bytes(count: 1 << 20)
        let textSize = SourceLoader.text(from: data).utf8.count
        #expect(textSize == data.count)
    }

    /// A slice's bytes before its start belong to the parent, not to the slice, so they must not make it binary.
    @Test
    func `a NUL before a slice's start does not count`() {
        let whole = Self.bytes(count: 100, nulAt: 0)
        let slice = whole.dropFirst()
        let text = SourceLoader.text(from: slice)
        #expect(text == String(repeating: "a", count: 99))
    }

    /// Empty data is an empty file, not a binary one.
    @Test
    func `empty data loads as empty text`() {
        #expect(SourceLoader.text(from: Data()) == "")
    }
}
