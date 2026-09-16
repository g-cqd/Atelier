import Foundation
import Testing

@testable import AtelierText

@Suite struct TextCursorTests {
    @Test func `default init produces zero position`() {
        let cursor = TextCursor()
        #expect(cursor.row == 0)
        #expect(cursor.col == 0)
        #expect(cursor.scrollRow == 0)
        #expect(cursor.scrollCol == 0)
    }

    @Test func `equality holds for identical values`() {
        let a = TextCursor(row: 3, col: 7, scrollRow: 1, scrollCol: 2)
        let b = TextCursor(row: 3, col: 7, scrollRow: 1, scrollCol: 2)
        #expect(a == b)
    }

    @Test func `inequality detected on any differing field`() {
        let base = TextCursor(row: 1, col: 2, scrollRow: 0, scrollCol: 0)
        #expect(base != TextCursor(row: 2, col: 2, scrollRow: 0, scrollCol: 0))
        #expect(base != TextCursor(row: 1, col: 3, scrollRow: 0, scrollCol: 0))
        #expect(base != TextCursor(row: 1, col: 2, scrollRow: 1, scrollCol: 0))
        #expect(base != TextCursor(row: 1, col: 2, scrollRow: 0, scrollCol: 1))
    }

    @Test func `clamp brings row within line count`() {
        let buffer = TextBuffer("a\nb\nc")
        var cursor = TextCursor(row: 10, col: 0)
        cursor.clamp(to: buffer)
        #expect(cursor.row == 2)
    }

    @Test func `clamp brings col within line length`() {
        let buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 99)
        cursor.clamp(to: buffer)
        #expect(cursor.col == 5)
    }

    @Test func `clamp allows col equal to line length (end of line)`() {
        let buffer = TextBuffer("hi")
        var cursor = TextCursor(row: 0, col: 2)
        cursor.clamp(to: buffer)
        #expect(cursor.col == 2)
    }

    @Test func `clamp does not move already valid cursor`() {
        let buffer = TextBuffer("hello\nworld")
        var cursor = TextCursor(row: 1, col: 3)
        cursor.clamp(to: buffer)
        #expect(cursor.row == 1)
        #expect(cursor.col == 3)
    }
}
