import Foundation
import Testing

@testable import AtelierText

@Suite struct TextOperationsDeleteRangeTests {
    @Test func `deleteRange same-line removes columns 6 to 11`() {
        var buffer = TextBuffer("hello world")
        var cursor = TextCursor(row: 0, col: 0)
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 6),
            head: TextPosition(row: 0, col: 11)
        )
        TextOperations.deleteRange(in: &buffer, at: &cursor, selection: selection)
        #expect(buffer.lines == ["hello "])
        #expect(cursor.row == 0)
        #expect(cursor.col == 6)
    }

    @Test func `deleteRange multi-line merges prefix of first with suffix of last`() {
        var buffer = TextBuffer("first line\nsecond line\nthird line")
        var cursor = TextCursor(row: 0, col: 0)
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 5),
            head: TextPosition(row: 2, col: 5)
        )
        TextOperations.deleteRange(in: &buffer, at: &cursor, selection: selection)
        #expect(buffer.lines == ["first line"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 5)
    }
}
