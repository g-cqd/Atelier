import Foundation
import Testing

@testable import KittyText

@Suite struct RopeTests {

    // MARK: - Construction

    @Test func `empty rope has zero bytes and one line`() {
        let sut = Rope()
        #expect(sut.byteCount == 0)
        #expect(sut.lineCount == 1)
        #expect(sut.text == "")
    }

    @Test func `init from empty string is equivalent to empty rope`() {
        let sut = Rope("")
        #expect(sut.byteCount == 0)
        #expect(sut.lineCount == 1)
    }

    @Test func `init from single line counts one line`() {
        let sut = Rope("hello")
        #expect(sut.byteCount == 5)
        #expect(sut.lineCount == 1)
        #expect(sut.text == "hello")
    }

    @Test func `init from multi-line string counts each newline-terminated line`() {
        let sut = Rope("foo\nbar\nbaz")
        #expect(sut.byteCount == 11)
        #expect(sut.lineCount == 3)
        #expect(sut.text == "foo\nbar\nbaz")
    }

    @Test func `trailing newline produces an extra empty line`() {
        let sut = Rope("foo\nbar\n")
        #expect(sut.lineCount == 3)
        #expect(sut.text == "foo\nbar\n")
    }

    @Test func `UTF-8 multi-byte content round-trips`() {
        let sut = Rope("héllo 世界 🇫🇷")
        #expect(sut.text == "héllo 世界 🇫🇷")
    }

    // MARK: - Line lookup

    @Test func `byteOffset(forLine:) returns start of each line`() {
        let sut = Rope("foo\nbar\nbaz")
        #expect(sut.byteOffset(forLine: 0) == 0)
        #expect(sut.byteOffset(forLine: 1) == 4)
        #expect(sut.byteOffset(forLine: 2) == 8)
    }

    @Test func `lineRange(forLine:) excludes terminating newline`() {
        let sut = Rope("foo\nbar\nbaz")
        #expect(sut.lineRange(forLine: 0) == 0..<3)
        #expect(sut.lineRange(forLine: 1) == 4..<7)
        #expect(sut.lineRange(forLine: 2) == 8..<11)
    }

    @Test func `lineRange for trailing empty line is empty range at end`() {
        let sut = Rope("foo\n")
        #expect(sut.lineCount == 2)
        #expect(sut.lineRange(forLine: 1) == 4..<4)
    }

    @Test func `line(at:) returns each line content`() {
        let sut = Rope("alpha\nbeta\ngamma")
        #expect(sut.line(at: 0) == "alpha")
        #expect(sut.line(at: 1) == "beta")
        #expect(sut.line(at: 2) == "gamma")
    }

    @Test func `line(at:) returns empty for out-of-bounds index`() {
        let sut = Rope("only")
        #expect(sut.line(at: -1) == "")
        #expect(sut.line(at: 1) == "")
    }

    // MARK: - Insert

    @Test func `insert at start prepends content`() {
        var sut = Rope("world")
        sut.insert("hello ", atByteOffset: 0)
        #expect(sut.text == "hello world")
    }

    @Test func `insert at end appends content`() {
        var sut = Rope("hello")
        sut.insert(" world", atByteOffset: 5)
        #expect(sut.text == "hello world")
    }

    @Test func `insert in the middle splits correctly`() {
        var sut = Rope("helloworld")
        sut.insert(", ", atByteOffset: 5)
        #expect(sut.text == "hello, world")
    }

    @Test func `inserting newline updates line count`() {
        var sut = Rope("hello world")
        sut.insert("\n", atByteOffset: 5)
        #expect(sut.lineCount == 2)
        #expect(sut.line(at: 0) == "hello")
        #expect(sut.line(at: 1) == " world")
    }

    @Test func `inserting multi-line string updates line count`() {
        var sut = Rope("ab")
        sut.insert("X\nY\nZ", atByteOffset: 1)
        #expect(sut.text == "aX\nY\nZb")
        #expect(sut.lineCount == 3)
    }

    @Test func `insert into empty rope produces single-line content`() {
        var sut = Rope()
        sut.insert("hello", atByteOffset: 0)
        #expect(sut.text == "hello")
        #expect(sut.lineCount == 1)
    }

    @Test func `insert clamps over-large offset`() {
        var sut = Rope("abc")
        sut.insert("X", atByteOffset: 999)
        #expect(sut.text == "abcX")
    }

    // MARK: - Remove

    @Test func `remove at start shrinks rope`() {
        var sut = Rope("hello world")
        sut.remove(0..<6)
        #expect(sut.text == "world")
    }

    @Test func `remove at end shrinks rope`() {
        var sut = Rope("hello world")
        sut.remove(5..<11)
        #expect(sut.text == "hello")
    }

    @Test func `remove crossing newline reduces line count`() {
        var sut = Rope("foo\nbar\nbaz")
        sut.remove(3..<8)
        #expect(sut.text == "foobaz")
        #expect(sut.lineCount == 1)
    }

    @Test func `remove of entire content yields empty rope`() {
        var sut = Rope("hello")
        sut.remove(0..<5)
        #expect(sut.byteCount == 0)
        #expect(sut.lineCount == 1)
        #expect(sut.text == "")
    }

    @Test func `remove out-of-range upper bound is clamped`() {
        var sut = Rope("hello")
        sut.remove(2..<999)
        #expect(sut.text == "he")
    }

    // MARK: - Replace

    @Test func `replace whole content`() {
        var sut = Rope("hello")
        sut.replace(0..<5, with: "world!")
        #expect(sut.text == "world!")
    }

    @Test func `replace first of three lines`() {
        var sut = Rope("abc\ndef\nghi")
        sut.replace(0..<3, with: "xyz")
        #expect(sut.text == "xyz\ndef\nghi")
        #expect(sut.lineCount == 3)
    }

    @Test func `replace last line content`() {
        var sut = Rope("abc\ndef")
        sut.replace(4..<7, with: "xyz")
        #expect(sut.text == "abc\nxyz")
    }

    @Test func `replace single line with multi-line content`() {
        var sut = Rope("middle")
        sut.replace(0..<6, with: "a\nb\nc")
        #expect(sut.text == "a\nb\nc")
        #expect(sut.lineCount == 3)
    }

    // MARK: - Bytes

    @Test func `bytes(in:) returns slice content`() {
        let sut = Rope("hello world")
        let slice = sut.bytes(in: 6..<11)
        #expect(String(decoding: slice, as: UTF8.self) == "world")
    }

    @Test func `bytes(in:) clamps over-large range`() {
        let sut = Rope("abc")
        let slice = sut.bytes(in: 1..<999)
        #expect(String(decoding: slice, as: UTF8.self) == "bc")
    }

    // MARK: - Value semantics

    @Test func `mutation does not affect copy`() {
        let original = Rope("hello")
        var copy = original
        copy.insert(" world", atByteOffset: 5)
        #expect(original.text == "hello")
        #expect(copy.text == "hello world")
    }

    @Test func `assigning back to variable preserves earlier snapshot`() {
        var sut = Rope("a")
        let snapshot1 = sut
        sut.insert("b", atByteOffset: 1)
        let snapshot2 = sut
        sut.insert("c", atByteOffset: 2)

        #expect(snapshot1.text == "a")
        #expect(snapshot2.text == "ab")
        #expect(sut.text == "abc")
    }

    // MARK: - Stress / scaling

    @Test func `large insert still produces correct content`() {
        var sut = Rope("")
        let chunk = String(repeating: "abcdefghij", count: 100)  // 1_000 bytes
        for _ in 0..<10 {
            sut.insert(chunk, atByteOffset: sut.byteCount)
        }
        #expect(sut.byteCount == 10_000)
        #expect(sut.text.hasPrefix("abcdef"))
        #expect(sut.text.hasSuffix("ghij"))
    }

    @Test func `many small inserts at start preserve order`() {
        var sut = Rope("")
        for index in 0..<200 {
            sut.insert("\(index % 10)", atByteOffset: 0)
        }
        #expect(sut.byteCount == 200)
    }

    @Test func `line count is preserved across 1000 line document`() {
        let lines = (0..<1_000).map { "line \($0)" }
        let sut = Rope(lines.joined(separator: "\n"))
        #expect(sut.lineCount == 1_000)
        #expect(sut.line(at: 0) == "line 0")
        #expect(sut.line(at: 999) == "line 999")
        #expect(sut.line(at: 500) == "line 500")
    }
}
