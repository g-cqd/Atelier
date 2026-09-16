import Foundation
import Testing

@testable import AtelierText

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

    @Test func `emoji presentation characters have display width 2`() {
        #expect(UnicodeWidth.displayWidth(of: "❌") == 2)
    }

    @Test func `emoji grapheme clusters have display width 2`() {
        #expect(UnicodeWidth.displayWidth(of: "1️⃣") == 2)
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

    // MARK: - Audit regressions (Unicode 15.1 gaps)

    @Test func `regional indicator pair is one grapheme of width 2`() {
        // 🇫🇷 — single grapheme cluster: U+1F1EB + U+1F1F7
        let flag: Character = "🇫🇷"
        #expect(UnicodeWidth.displayWidth(of: flag) == 2)
    }

    @Test func `ZWJ family sequence has display width 2`() {
        // 👨‍👩‍👧 — family ZWJ sequence
        let family: Character = "👨‍👩‍👧"
        #expect(UnicodeWidth.displayWidth(of: family) == 2)
    }

    @Test func `emoji modifier sequence has display width 2`() {
        // 👍🏽 — thumbs up with Fitzpatrick skin tone modifier
        let thumbsUp: Character = "👍🏽"
        #expect(UnicodeWidth.displayWidth(of: thumbsUp) == 2)
    }

    @Test func `text variation selector keeps emoji at width 2 when presentation is emoji`() {
        // ❤️ — heavy black heart with VS16 (emoji presentation)
        let heart: Character = "❤️"
        #expect(UnicodeWidth.displayWidth(of: heart) == 2)
    }

    @Test func `mixed RI plus ASCII string sums widths correctly`() {
        // "A" (1) + "🇯🇵" (2) + "B" (1) = 4
        #expect(UnicodeWidth.displayWidth(of: "A🇯🇵B") == 4)
    }

    @Test func `CJK compatibility ideograph has display width 2`() {
        // U+F900 豈 — CJK Compatibility Ideograph; covered by isIdeographic.
        #expect(UnicodeWidth.displayWidth(of: "豈") == 2)
    }

    @Test func `CJK extension B ideograph has display width 2`() {
        // U+20000 𠀀 — CJK Extension B, plane 2 (SMP).
        #expect(UnicodeWidth.displayWidth(of: "𠀀") == 2)
    }

    @Test func `Kangxi radical has display width 2`() {
        // U+2F00 ⼀ — Kangxi Radical One.
        #expect(UnicodeWidth.displayWidth(of: "⼀") == 2)
    }

    @Test func `Hiragana character has display width 2`() {
        // U+3042 あ — Hiragana.
        #expect(UnicodeWidth.displayWidth(of: "あ") == 2)
    }

    @Test func `CJK Symbols and Punctuation has display width 2`() {
        // U+3001 、 — CJK ideographic comma.
        #expect(UnicodeWidth.displayWidth(of: "、") == 2)
    }

    @Test func `Latin character above 0x1100 narrow remains width 1`() {
        // U+1E00 Ḁ — Latin Extended Additional, narrow.
        #expect(UnicodeWidth.displayWidth(of: "Ḁ") == 1)
    }
}
