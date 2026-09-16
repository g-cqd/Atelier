import Foundation
import Testing

@testable import AtelierText

@Suite struct TextOperationsTests {
    @Test func `insert adds text at cursor column`() {
        var buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 5)
        let mutation = TextOperations.insert(" world", into: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hello world")
        #expect(cursor.col == 11)
        #expect(mutation.originalLineRange == 0 ..< 1)
        #expect(mutation.updatedLineRange == 0 ..< 1)
    }

    @Test func `insert mid-line splits correctly`() {
        var buffer = TextBuffer("helloworld")
        var cursor = TextCursor(row: 0, col: 5)
        TextOperations.insert(" ", into: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hello world")
        #expect(cursor.col == 6)
    }

    @Test func `insert into empty buffer populates first line`() {
        var buffer = TextBuffer("")
        var cursor = TextCursor(row: 0, col: 0)
        TextOperations.insert("x", into: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "x")
        #expect(cursor.col == 1)
    }

    @Test func `insertNewline splits line at cursor`() {
        var buffer = TextBuffer("hello world")
        var cursor = TextCursor(row: 0, col: 5)
        let mutation = TextOperations.insertNewline(into: &buffer, at: &cursor)
        #expect(buffer.lines == ["hello", " world"])
        #expect(cursor.row == 1)
        #expect(cursor.col == 0)
        #expect(mutation.originalLineRange == 0 ..< 1)
        #expect(mutation.updatedLineRange == 0 ..< 2)
    }

    @Test func `insert splits into multiple lines when text contains newlines`() {
        var buffer = TextBuffer("prefixsuffix")
        var cursor = TextCursor(row: 0, col: 6)
        let mutation = TextOperations.insert(" one\ntwo\nthree ", into: &buffer, at: &cursor)

        #expect(buffer.lines == ["prefix one", "two", "three suffix"])
        #expect(cursor.row == 2)
        #expect(cursor.col == 6)
        #expect(mutation.originalLineRange == 0 ..< 1)
        #expect(mutation.updatedLineRange == 0 ..< 3)
    }

    @Test func `insertNewline at start of line inserts blank line above`() {
        var buffer = TextBuffer("content")
        var cursor = TextCursor(row: 0, col: 0)
        TextOperations.insertNewline(into: &buffer, at: &cursor)
        #expect(buffer.lines == ["", "content"])
        #expect(cursor.row == 1)
        #expect(cursor.col == 0)
    }

    @Test func `insertNewline at end of line appends empty line`() {
        var buffer = TextBuffer("content")
        var cursor = TextCursor(row: 0, col: 7)
        TextOperations.insertNewline(into: &buffer, at: &cursor)
        #expect(buffer.lines == ["content", ""])
        #expect(cursor.row == 1)
        #expect(cursor.col == 0)
    }

    @Test func `deleteBackward removes character before cursor`() {
        var buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 5)
        let mutation = TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hell")
        #expect(cursor.col == 4)
        #expect(mutation?.originalLineRange == 0 ..< 1)
        #expect(mutation?.updatedLineRange == 0 ..< 1)
    }

    @Test func `deleteBackward mid-line removes correct character`() {
        var buffer = TextBuffer("abcde")
        var cursor = TextCursor(row: 0, col: 3)
        TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "abde")
        #expect(cursor.col == 2)
    }

    @Test func `deleteBackward at column 0 merges with previous line`() {
        var buffer = TextBuffer("first\nsecond")
        var cursor = TextCursor(row: 1, col: 0)
        let mutation = TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["firstsecond"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 5)
        #expect(mutation?.originalLineRange == 0 ..< 2)
        #expect(mutation?.updatedLineRange == 0 ..< 1)
    }

    @Test func `deleteBackward at row 0 column 0 is a no-op`() {
        var buffer = TextBuffer("text")
        var cursor = TextCursor(row: 0, col: 0)
        let mutation = TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["text"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 0)
        #expect(mutation == nil)
    }
}
