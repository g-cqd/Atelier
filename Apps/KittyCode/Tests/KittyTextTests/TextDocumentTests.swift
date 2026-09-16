import Foundation
import Testing

@testable import KittyText

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

    @Test func `detectLineEnding recognizes common newline sequences`() {
        #expect(TextDocument.detectLineEnding(in: Data("alpha\nbeta\n".utf8)) == .lineFeed)
        #expect(TextDocument.detectLineEnding(in: Data("alpha\r\nbeta\r\n".utf8)) == .carriageReturnLineFeed)
        #expect(TextDocument.detectLineEnding(in: Data("alpha\rbeta\r".utf8)) == .carriageReturn)
        #expect(TextDocument.detectLineEnding(in: Data("alpha".utf8)) == .lineFeed)
    }
}
