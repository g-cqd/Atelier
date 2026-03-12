import Foundation
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

    @Test func `init from multiline string preserves trailing empty line`() {
        let buffer = TextBuffer("foo\nbar\n")
        #expect(buffer.lines == ["foo", "bar", ""])
        #expect(buffer.lineCount == 3)
        #expect(buffer.text == "foo\nbar\n")
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

// MARK: - TextDocument

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

// MARK: - TextDisplayMetrics

@Suite struct TextDisplayMetricsTests {
    @Test func `displayColumn counts wide characters`() {
        #expect(TextDisplayMetrics.displayColumn(forCharacterOffset: 0, in: "a界b") == 0)
        #expect(TextDisplayMetrics.displayColumn(forCharacterOffset: 2, in: "a界b") == 3)
    }

    @Test func `characterOffset maps display columns back to character offsets`() {
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 0, in: "a界b") == 0)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 1, in: "a界b") == 1)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 3, in: "a界b") == 2)
    }

    @Test func `lineNumberDigits grows past five digits`() {
        #expect(TextDisplayMetrics.lineNumberDigits(forLineCount: 9) == 1)
        #expect(TextDisplayMetrics.lineNumberDigits(forLineCount: 10) == 2)
        #expect(TextDisplayMetrics.lineNumberDigits(forLineCount: 100_000) == 6)
    }

    @Test func `isPrintable rejects ASCII control characters`() {
        #expect(Character("A").isPrintable)
        #expect(!Character("\u{7}").isPrintable)
    }
}

// MARK: - TextOperations

@Suite struct TextOperationsTests {
    @Test func `insert adds text at cursor column`() {
        var buffer = TextBuffer("hello")
        var cursor = TextCursor(row: 0, col: 5)
        let mutation = TextOperations.insert(" world", into: &buffer, at: &cursor)
        #expect(buffer.lines[0] == "hello world")
        #expect(cursor.col == 11)
        #expect(mutation.originalLineRange == 0..<1)
        #expect(mutation.updatedLineRange == 0..<1)
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
        #expect(mutation.originalLineRange == 0..<1)
        #expect(mutation.updatedLineRange == 0..<2)
    }

    @Test func `insert splits into multiple lines when text contains newlines`() {
        var buffer = TextBuffer("prefixsuffix")
        var cursor = TextCursor(row: 0, col: 6)
        let mutation = TextOperations.insert(" one\ntwo\nthree ", into: &buffer, at: &cursor)

        #expect(buffer.lines == ["prefix one", "two", "three suffix"])
        #expect(cursor.row == 2)
        #expect(cursor.col == 6)
        #expect(mutation.originalLineRange == 0..<1)
        #expect(mutation.updatedLineRange == 0..<3)
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
        #expect(mutation?.originalLineRange == 0..<1)
        #expect(mutation?.updatedLineRange == 0..<1)
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
        #expect(mutation?.originalLineRange == 0..<2)
        #expect(mutation?.updatedLineRange == 0..<1)
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

// MARK: - TextOperations.deleteRange

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

// MARK: - TextSelection.extractText

@Suite struct TextSelectionExtractionTests {
    @Test func `extractText single-line selection`() {
        let lines = ["hello world"]
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 6),
            head: TextPosition(row: 0, col: 11)
        )
        let result = selection.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(result == "world")
    }

    @Test func `extractText multi-line selection`() {
        let lines = ["first", "middle", "last"]
        let selection = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 2, col: 3)
        )
        let result = selection.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(result == "rst\nmiddle\nlas")
    }

    @Test func `extractText reversed selection produces same result as forward`() {
        let lines = ["first", "middle", "last"]
        let forward = TextSelection(
            anchor: TextPosition(row: 0, col: 2),
            head: TextPosition(row: 2, col: 3)
        )
        let reversed = TextSelection(
            anchor: TextPosition(row: 2, col: 3),
            head: TextPosition(row: 0, col: 2)
        )
        let forwardResult = forward.extractText(from: { lines[$0] }, lineCount: lines.count)
        let reversedResult = reversed.extractText(from: { lines[$0] }, lineCount: lines.count)
        #expect(forwardResult == reversedResult)
    }
}

// MARK: - TextSanitizer

@Suite struct TextSanitizerTests {
    @Test func `sanitize replaces BEL control character`() {
        let result = TextSanitizer.sanitize("\u{07}")
        #expect(result.replacedCount == 1)
        #expect(!result.text.contains("\u{07}"))
    }

    @Test func `sanitize passes newline and tab, strips zero-width characters`() {
        let input = "\t\n\u{200B}\u{FEFF}"
        let result = TextSanitizer.sanitize(input)
        #expect(result.text.contains("\t"))
        #expect(result.text.contains("\n"))
        #expect(!result.text.contains("\u{200B}"))
        #expect(!result.text.contains("\u{FEFF}"))
        #expect(result.replacedCount == 2)
    }
}

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
