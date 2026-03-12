import Foundation
import Testing

@testable import KittyText

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
