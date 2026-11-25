import AtelierSyntaxModel
import Testing

@testable import AtelierDocComment

@Suite
struct LexicalIdentifierLocatorTests {
    private func identifier(_ text: String, _ language: Language = .typescript, line: Int, column: Int) -> String? {
        LexicalIdentifierLocator.identifier(in: text, language: language, line: line, utf16Column: column)
    }

    @Test
    func `the identifier under the position, or ending right before it, is found`() {
        let text = "const total = sumAll(items);\n"

        #expect(identifier(text, line: 0, column: 14) == "sumAll")
        #expect(identifier(text, line: 0, column: 17) == "sumAll")
        #expect(identifier(text, line: 0, column: 20) == "sumAll")
        #expect(identifier(text, line: 0, column: 21) == "items")
    }

    @Test
    func `columns count UTF-16 units, so an emoji before the name counts two`() {
        // "🙂" is two UTF-16 units: `name` spans columns 14 to 17, where it would span 13 to 16 in characters.
        let text = "let a = \"🙂\"; name.go()\nlet é = café"

        #expect(identifier(text, line: 0, column: 15) == "name")
        #expect(identifier(text, line: 0, column: 17) == "name")
        #expect(identifier(text, line: 0, column: 19) == "go")
        #expect(identifier(text, line: 0, column: 9) == nil)
        #expect(identifier(text, line: 1, column: 10) == "café")
        #expect(identifier(text, line: 1, column: 4) == "é")
    }

    @Test
    func `a keyword, a literal, a comment or punctuation has no identifier`() {
        let text = "function f() { return \"text\" + 42; } // note\n"

        #expect(identifier(text, line: 0, column: 2) == nil)
        #expect(identifier(text, line: 0, column: 24) == nil)
        #expect(identifier(text, line: 0, column: 32) == nil)
        #expect(identifier(text, line: 0, column: 42) == nil)
        #expect(identifier(text, line: 0, column: 13) == nil)
    }

    @Test
    func `a position past the line or the text has no identifier`() {
        #expect(identifier("a\nb", line: 0, column: 5) == nil)
        #expect(identifier("a\nb", line: 3, column: 0) == nil)
        #expect(identifier("a\nb", line: 1, column: 0) == "b")
    }

    @Test
    func `a dollar sign is part of a JavaScript name, not of a Go one`() {
        #expect(identifier("$store.get()", .javascript, line: 0, column: 2) == "$store")
        #expect(identifier("x := a$b", .go, line: 0, column: 5) == "a")
    }

    @Test
    func `a capitalised name, which the scanner colours as a type, is an identifier`() {
        #expect(identifier("var r *Reader", .go, line: 0, column: 9) == "Reader")
    }
}
