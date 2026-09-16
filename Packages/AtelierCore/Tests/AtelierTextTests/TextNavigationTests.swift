import Foundation
import Testing

@testable import AtelierText

@Suite struct TextNavigationTests {
    @Test func `moveWordForward advances past word then whitespace`() {
        let buffer = TextBuffer("alpha   beta")
        var cursor = TextCursor(row: 0, col: 0)
        TextNavigation.moveWordForward(cursor: &cursor, in: buffer)
        #expect(cursor.col == 8)
    }

    @Test func `moveWordForward at end of line does nothing`() {
        let buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 5)
        TextNavigation.moveWordForward(cursor: &cursor, in: buffer)
        #expect(cursor.col == 5)
    }

    @Test func `moveWordForward stops at end when no next word`() {
        let buffer = TextBuffer("word")
        var cursor = TextCursor(row: 0, col: 0)
        TextNavigation.moveWordForward(cursor: &cursor, in: buffer)
        #expect(cursor.col == 4)
    }

    @Test func `moveWordBackward moves to start of previous word`() {
        let buffer = TextBuffer("alpha   beta")
        var cursor = TextCursor(row: 0, col: 12)
        TextNavigation.moveWordBackward(cursor: &cursor, in: buffer)
        #expect(cursor.col == 8)
    }

    @Test func `moveWordBackward at column 0 does nothing`() {
        let buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 0)
        TextNavigation.moveWordBackward(cursor: &cursor, in: buffer)
        #expect(cursor.col == 0)
    }

    @Test func `ensureVisible scrolls down when cursor is below viewport`() {
        var cursor = TextCursor(row: 15, col: 0, scrollRow: 0, scrollCol: 0)
        TextNavigation.ensureVisible(
            cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 6)
    }

    @Test func `ensureVisible scrolls up when cursor is above viewport`() {
        var cursor = TextCursor(row: 2, col: 0, scrollRow: 10, scrollCol: 0)
        TextNavigation.ensureVisible(
            cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 2)
    }

    @Test func `ensureVisible adjusts horizontal scroll when cursor is right of viewport`() {
        var cursor = TextCursor(row: 0, col: 25, scrollRow: 0, scrollCol: 0)
        TextNavigation.ensureVisible(
            cursor: &cursor, visibleRows: 10, visibleCols: 8, wrapLines: false)
        #expect(cursor.scrollCol == 18)
    }

    @Test func `ensureVisible resets horizontal scroll when wrapLines is true`() {
        var cursor = TextCursor(row: 0, col: 50, scrollRow: 0, scrollCol: 30)
        TextNavigation.ensureVisible(
            cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: true)
        #expect(cursor.scrollCol == 0)
    }

    @Test func `ensureVisible does not move scroll when cursor is already visible`() {
        var cursor = TextCursor(row: 5, col: 5, scrollRow: 0, scrollCol: 0)
        TextNavigation.ensureVisible(
            cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 0)
        #expect(cursor.scrollCol == 0)
    }
}
