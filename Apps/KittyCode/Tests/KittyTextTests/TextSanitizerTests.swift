import Foundation
import Testing

@testable import KittyText

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
