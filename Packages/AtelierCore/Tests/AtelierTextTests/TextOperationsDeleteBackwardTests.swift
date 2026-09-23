import Testing

@testable import AtelierText

/// Backspace with a column the line no longer has, as a replace-all that shortens the line leaves it.
struct TextOperationsDeleteBackwardTests {
    @Test(arguments: [4, 10, 1_000, Int.max])
    func `a column past the line end deletes the line's last character`(column: Int) {
        var buffer = TextBuffer("abc\ndef")
        var cursor = TextCursor(row: 1, col: column)
        let mutation = TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["abc", "de"])
        #expect(cursor.row == 1)
        #expect(cursor.col == 2)
        #expect(mutation?.originalLineRange == 1 ..< 2)
    }
}
