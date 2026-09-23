import Testing

@testable import AtelierText

/// Pasted text reaches the document and then the terminal, so a paste keeps no control but tab and line feed; the
/// predicate it shares with the terminal renderer names exactly the C0 controls, DEL and the C1 controls.
@Suite
struct TextSanitizerControlTests {
    @Test(arguments: [0x00, 0x07, 0x0D, 0x1B, 0x7F] + Array(0x80 ... 0x9F))
    func `a pasted control other than tab and line feed is removed`(value: UInt32) throws {
        let scalar = try #require(Unicode.Scalar(value))

        let result = TextSanitizer.sanitize("a\(Character(scalar))b")

        #expect(result.text == "ab")
        #expect(result.replacedCount == 1)
    }

    @Test
    func `pasted tabs and line feeds are kept`() {
        let result = TextSanitizer.sanitize("a\tb\nc")

        #expect(result.text == "a\tb\nc")
        #expect(result.replacedCount == 0)
    }

    @Test
    func `the control predicate holds exactly C0, DEL and C1`() {
        let controls = (0 ... 0x10FFFF as ClosedRange<UInt32>).compactMap(Unicode.Scalar.init)
            .filter(TextSanitizer.isControl).map(\.value)

        #expect(controls == Array(0x00 ... 0x1F) + [0x7F] + Array(0x80 ... 0x9F))
    }
}
