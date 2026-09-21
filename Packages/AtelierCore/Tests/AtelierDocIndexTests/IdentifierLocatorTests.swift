import Testing

@testable import AtelierDocIndex

struct IdentifierLocatorTests {
    @Test
    func `hits mid identifier`() {
        // "let value = 1" -> "value" spans utf16 columns 4..<9
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 0, utf16Column: 6)
        #expect(name == "value")
    }

    @Test
    func `hits first character of identifier`() {
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 0, utf16Column: 4)
        #expect(name == "value")
    }

    @Test
    func `hits last character of identifier`() {
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 0, utf16Column: 8)
        #expect(name == "value")
    }

    @Test
    func `keyword resolves to nil`() {
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 0, utf16Column: 1)
        #expect(name == nil)
    }

    @Test
    func `string literal resolves to nil`() {
        let name = IdentifierLocator.identifier(in: "let s = \"hello\"", line: 0, utf16Column: 10)
        #expect(name == nil)
    }

    @Test
    func `whitespace resolves to nil`() {
        let name = IdentifierLocator.identifier(in: "let  value = 1", line: 0, utf16Column: 4)
        #expect(name == nil)
    }

    @Test
    func `emoji before the identifier shifts the utf16 column correctly`() {
        // "// 😀 value" -- 😀 is a surrogate pair (2 utf16 units); "value" starts at utf16 column 6.
        let text = "// \u{1F600} value"
        let name = IdentifierLocator.identifier(in: text, line: 0, utf16Column: 6)
        #expect(name == nil)  // inside a line comment, not an identifier token
    }

    @Test
    func `emoji before the identifier on a code line`() {
        let text = "let \u{1F600}x = 1"
        // "\u{1F600}x" is the identifier "😀x": 😀 is 2 utf16 units, so the identifier spans columns 4..<7.
        let name = IdentifierLocator.identifier(in: text, line: 0, utf16Column: 6)
        #expect(name == "\u{1F600}x")
    }

    @Test
    func `backticked identifier strips the backticks`() {
        let name = IdentifierLocator.identifier(in: "let `class` = 1", line: 0, utf16Column: 6)
        #expect(name == "class")
    }

    @Test
    func `out of range line resolves to nil`() {
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 5, utf16Column: 0)
        #expect(name == nil)
    }

    @Test
    func `out of range column resolves to nil`() {
        let name = IdentifierLocator.identifier(in: "let value = 1", line: 0, utf16Column: 500)
        #expect(name == nil)
    }
}
