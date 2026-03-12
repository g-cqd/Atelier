import Foundation
import Testing

@testable import KittyText

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
