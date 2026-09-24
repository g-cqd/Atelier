import AtelierText
import Testing

@testable import KittyEditor

/// A rope's lines read as one run of text are the lines `lines(in:)` reads, joined by `\n`.
struct JoinedLineTextTests {
    private static let buffer = TextBuffer(lines: ["let a = 1", "", "  // héllo 🙂 wörld", "\tb", "", "last"])

    @Test(arguments: [0 ..< 6, 1 ..< 3, 2 ..< 3, 5 ..< 6, 4 ..< 10, -3 ..< 2, 3 ..< 3, 6 ..< 9])
    func `a run of lines reads as those lines joined by newlines`(range: Range<Int>) {
        #expect(Self.buffer.joinedText(ofLines: range) == Self.buffer.lines(in: range).joined(separator: "\n"))
    }

    @Test
    func `an empty document reads as empty text`() {
        let empty = TextBuffer(lines: [""])

        #expect(empty.joinedText(ofLines: 0 ..< 1) == "")
    }
}
