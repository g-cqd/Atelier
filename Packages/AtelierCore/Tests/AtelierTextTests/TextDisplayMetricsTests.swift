import Foundation
import Testing

@testable import AtelierText

@Suite struct TextDisplayMetricsTests {
    @Test func `displayColumn counts wide characters`() {
        #expect(TextDisplayMetrics.displayColumn(forCharacterOffset: 0, in: "a界b") == 0)
        #expect(TextDisplayMetrics.displayColumn(forCharacterOffset: 2, in: "a界b") == 3)
    }

    @Test func `characterOffset maps display columns back to character offsets`() {
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 0, in: "a界b") == 0)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 1, in: "a界b") == 1)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 2, in: "a界b") == 1)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 3, in: "a界b") == 2)
    }

    @Test func `characterOffset stays on the owning tab while inside its span`() {
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 1, in: "\tab", tabSize: 4) == 0)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 3, in: "\tab", tabSize: 4) == 0)
        #expect(TextDisplayMetrics.characterOffset(forDisplayColumn: 4, in: "\tab", tabSize: 4) == 1)
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
