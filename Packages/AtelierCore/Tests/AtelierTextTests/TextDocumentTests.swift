import Foundation
import Testing

@testable import AtelierText

@Suite
@MainActor
struct TextDocumentTests {
    @Test func `init keeps first paint data in TextBuffer without eager snapshots`() {
        let document = TextDocument(
            filePath: "/tmp/example.txt",
            fileName: "example.txt",
            content: "alpha\nbeta",
            language: "txt"
        )

        #expect(document.fileLineCount == 2)
        #expect(document.line(at: 0) == "alpha")
        #expect(document.line(at: 1) == "beta")
        #expect(document.cachedFileLines == nil)
        #expect(document.cachedDocumentText == nil)
        #expect(document.cachedMaxLineWidth == nil)
    }

    @Test func `fileContent materializes and caches line snapshots on demand`() {
        let document = TextDocument(
            filePath: "/tmp/example.txt",
            fileName: "example.txt",
            content: "alpha\nbeta",
            language: nil
        )

        #expect(document.fileContent == ["alpha", "beta"])
        #expect(document.cachedFileLines == ["alpha", "beta"])
    }

    @Test func `serializedText preserves configured line endings and byte count`() {
        let document = TextDocument(
            filePath: "/tmp/example.txt",
            fileName: "example.txt",
            content: "alpha\nbeta\n",
            language: nil,
            lineEnding: .carriageReturnLineFeed
        )

        #expect(document.serializedText() == "alpha\r\nbeta\r\n")
        #expect(document.serializedByteCount == "alpha\r\nbeta\r\n".utf8.count)
    }

    @Test(arguments: [TextDocument.LineEnding.lineFeed, .carriageReturnLineFeed, .carriageReturn])
    func `serializing serialized text changes nothing`(lineEnding: TextDocument.LineEnding) {
        let once = TextDocument.serializedText(from: "alpha\nbeta\r\ngamma\rdelta\n", lineEnding: lineEnding)
        #expect(TextDocument.serializedText(from: once, lineEnding: lineEnding) == once)
    }

    @Test func `serializing writes every kind of line break in the target ending`() {
        let serialized = TextDocument.serializedText(from: "a\nb\r\nc\rd", lineEnding: .carriageReturnLineFeed)
        #expect(Array(serialized.utf8) == Array("a\r\nb\r\nc\r\nd".utf8))
    }

    @Test func `normalizing turns CRLF and lone CR into LF and leaves LF text as it is`() {
        #expect(Array(TextDocument.normalizingLineBreaks("a\r\nb\rc\n\r\n").utf8) == Array("a\nb\nc\n\n".utf8))
        #expect(TextDocument.normalizingLineBreaks("a\nb\n") == "a\nb\n")
    }

    @Test func `detectLineEnding recognizes common newline sequences`() {
        #expect(TextDocument.detectLineEnding(in: Data("alpha\nbeta\n".utf8)) == .lineFeed)
        #expect(TextDocument.detectLineEnding(in: Data("alpha\r\nbeta\r\n".utf8)) == .carriageReturnLineFeed)
        #expect(TextDocument.detectLineEnding(in: Data("alpha\rbeta\r".utf8)) == .carriageReturn)
        #expect(TextDocument.detectLineEnding(in: Data("alpha".utf8)) == .lineFeed)
    }
}
