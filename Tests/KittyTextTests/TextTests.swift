import Testing
@testable import KittyText

// MARK: - TextBuffer

@Suite struct TextBufferTests {
    @Test func `init from empty string produces single empty line`() {
        let buffer = TextBuffer("")
        #expect(buffer.lines == [""])
        #expect(buffer.lineCount == 1)
        #expect(buffer.isEmpty)
    }

    @Test func `init from single-line string`() {
        let buffer = TextBuffer("hello")
        #expect(buffer.lines == ["hello"])
        #expect(buffer.lineCount == 1)
        #expect(!buffer.isEmpty)
    }

    @Test func `init from multiline string splits on newline`() {
        let buffer = TextBuffer("foo\nbar\nbaz")
        #expect(buffer.lines == ["foo", "bar", "baz"])
        #expect(buffer.lineCount == 3)
    }

    @Test func `init from empty lines array produces single empty line`() {
        let buffer = TextBuffer(lines: [])
        #expect(buffer.lines == [""])
        #expect(buffer.isEmpty)
    }

    @Test func `init from non-empty lines array preserves lines`() {
        let buffer = TextBuffer(lines: ["alpha", "beta"])
        #expect(buffer.lines == ["alpha", "beta"])
        #expect(buffer.lineCount == 2)
    }

    @Test func `line(at:) returns correct content`() {
        let buffer = TextBuffer("first\nsecond\nthird")
        #expect(buffer.line(at: 0) == "first")
        #expect(buffer.line(at: 1) == "second")
        #expect(buffer.line(at: 2) == "third")
    }

    @Test func `line(at:) returns empty string for out of bounds index`() {
        let buffer = TextBuffer("only")
        #expect(buffer.line(at: -1) == "")
        #expect(buffer.line(at: 1) == "")
    }

    @Test func `text round-trips through init`() {
        let original = "line one\nline two\nline three"
        let buffer = TextBuffer(original)
        #expect(buffer.text == original)
    }

    @Test func `isEmpty is false for non-empty single line`() {
        let buffer = TextBuffer("x")
        #expect(!buffer.isEmpty)
    }

    @Test func `isEmpty is false for multi-line buffer`() {
        let buffer = TextBuffer("\n")
        #expect(!buffer.isEmpty)
        #expect(buffer.lineCount == 2)
    }
}

// MARK: - TextCursor

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

// MARK: - TextNavigation

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
        TextNavigation.ensureVisible(cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 6)
    }

    @Test func `ensureVisible scrolls up when cursor is above viewport`() {
        var cursor = TextCursor(row: 2, col: 0, scrollRow: 10, scrollCol: 0)
        TextNavigation.ensureVisible(cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 2)
    }

    @Test func `ensureVisible adjusts horizontal scroll when cursor is right of viewport`() {
        var cursor = TextCursor(row: 0, col: 25, scrollRow: 0, scrollCol: 0)
        TextNavigation.ensureVisible(cursor: &cursor, visibleRows: 10, visibleCols: 8, wrapLines: false)
        #expect(cursor.scrollCol == 18)
    }

    @Test func `ensureVisible resets horizontal scroll when wrapLines is true`() {
        var cursor = TextCursor(row: 0, col: 50, scrollRow: 0, scrollCol: 30)
        TextNavigation.ensureVisible(cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: true)
        #expect(cursor.scrollCol == 0)
    }

    @Test func `ensureVisible does not move scroll when cursor is already visible`() {
        var cursor = TextCursor(row: 5, col: 5, scrollRow: 0, scrollCol: 0)
        TextNavigation.ensureVisible(cursor: &cursor, visibleRows: 10, visibleCols: 80, wrapLines: false)
        #expect(cursor.scrollRow == 0)
        #expect(cursor.scrollCol == 0)
    }
}

// MARK: - TextOperations

@Suite struct TextOperationsTests {
    @Test func `insert adds text at cursor column`() {
        var buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 5)
        TextOperations.insert(" world", into: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hello world")
        #expect(cursor.col == 11)
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
        TextOperations.insertNewline(into: &buffer, at: &cursor)
        #expect(buffer.lines == ["hello", " world"])
        #expect(cursor.row == 1)
        #expect(cursor.col == 0)
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
        TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hell")
        #expect(cursor.col == 4)
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
        TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["firstsecond"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 5)
    }

    @Test func `deleteBackward at row 0 column 0 is a no-op`() {
        var buffer = TextBuffer("text")
        var cursor = TextCursor(row: 0, col: 0)
        TextOperations.deleteBackward(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["text"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 0)
    }
}

// MARK: - TextSelection

@Suite struct TextSelectionTests {
    @Test func `isCollapsed when anchor equals head`() {
        let pos = TextPosition(row: 2, col: 4)
        let sel = TextSelection(anchor: pos, head: pos)
        #expect(sel.isCollapsed)
    }

    @Test func `isCollapsed is false when anchor differs from head`() {
        let sel = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )
        #expect(!sel.isCollapsed)
    }

    @Test func `ordered returns anchor first when anchor is before head`() {
        let anchor = TextPosition(row: 1, col: 2)
        let head = TextPosition(row: 3, col: 0)
        let sel = TextSelection(anchor: anchor, head: head)
        let (start, end) = sel.ordered
        #expect(start == anchor)
        #expect(end == head)
    }

    @Test func `ordered returns head first when head is before anchor`() {
        let anchor = TextPosition(row: 5, col: 0)
        let head = TextPosition(row: 2, col: 8)
        let sel = TextSelection(anchor: anchor, head: head)
        let (start, end) = sel.ordered
        #expect(start == head)
        #expect(end == anchor)
    }

    @Test func `TextPosition comparison is row-major`() {
        let earlier = TextPosition(row: 1, col: 99)
        let later = TextPosition(row: 2, col: 0)
        #expect(earlier < later)
    }

    @Test func `TextPosition comparison uses col when rows are equal`() {
        let left = TextPosition(row: 3, col: 4)
        let right = TextPosition(row: 3, col: 10)
        #expect(left < right)
    }
}

// MARK: - UnicodeWidth

@Suite struct UnicodeWidthTests {
    @Test func `ASCII letter has display width 1`() {
        #expect(UnicodeWidth.displayWidth(of: "A") == 1)
        #expect(UnicodeWidth.displayWidth(of: "z") == 1)
    }

    @Test func `ASCII digit has display width 1`() {
        #expect(UnicodeWidth.displayWidth(of: "9") == 1)
    }

    @Test func `CJK unified ideograph has display width 2`() {
        // U+4E2D 中
        #expect(UnicodeWidth.displayWidth(of: "中") == 2)
    }

    @Test func `Hangul syllable has display width 2`() {
        // U+AC00 가
        #expect(UnicodeWidth.displayWidth(of: "가") == 2)
    }

    @Test func `fullwidth Latin has display width 2`() {
        // U+FF21 Ａ
        #expect(UnicodeWidth.displayWidth(of: "Ａ") == 2)
    }

    @Test func `null character has display width 0`() {
        #expect(UnicodeWidth.displayWidth(of: "\0") == 0)
    }

    @Test func `string width sums character widths`() {
        // "Hi" (2) + "中" (2) = 4
        #expect(UnicodeWidth.displayWidth(of: "Hi中") == 4)
    }

    @Test func `empty string has display width 0`() {
        #expect(UnicodeWidth.displayWidth(of: "") == 0)
    }

    @Test func `ASCII-only string width equals character count`() {
        let s = "Hello"
        #expect(UnicodeWidth.displayWidth(of: s) == s.count)
    }
}
