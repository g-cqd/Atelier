import Foundation
import Testing

@testable import AtelierText
@testable import KittyWorkspace

@Suite
@MainActor
struct DocumentBufferReloadTests {
    @Test
    func `a reload installs the rope its read built`() throws {
        let buffer = DocumentBuffer(
            filePath: "/project/notes.txt", fileName: "notes.txt", content: "old", language: nil)
        let loadedFile = try WorkspaceFileLoading.decode(Data("new\r\ntext\r\n".utf8))
        // Materialised on the read's rope only: a rope rebuilt from the text on the main actor starts without them.
        _ = loadedFile.textBuffer.lines

        _ = buffer.replaceContents(with: loadedFile, modifiedAt: nil)

        #expect(!buffer.textBuffer._testSnapshotCachesAreEmpty)
        #expect(buffer.textBuffer.lines(in: 0 ..< buffer.textBuffer.lineCount) == ["new", "text", ""])
    }
}
