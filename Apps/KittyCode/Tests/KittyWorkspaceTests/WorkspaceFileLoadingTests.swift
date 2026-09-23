import AtelierText
import Foundation
import Testing

@testable import KittyWorkspace

@Suite
struct WorkspaceFileLoadingTests {
    @Test(arguments: [
        ("a\nb\n", TextDocument.LineEnding.lineFeed), ("a\r\nb\r\n", .carriageReturnLineFeed),
        ("a\rb\r", .carriageReturn)
    ])
    func `a file loads with LF line breaks and remembers the ending it used`(
        bytes: String, lineEnding: TextDocument.LineEnding
    ) throws {
        let loaded = try WorkspaceFileLoading.decode(Data(bytes.utf8))

        #expect(Array(loaded.content.utf8) == Array("a\nb\n".utf8))
        #expect(loaded.lineEnding == lineEnding)
    }

    @Test func `bytes that are not UTF-8 are refused`() {
        #expect(throws: CocoaError.self) {
            try WorkspaceFileLoading.decode(Data([0x61, 0xFF, 0x62]))
        }
    }
}
