import AtelierParser
import Testing

@testable import AtelierScanners

struct RustExternalScannerTests {
    private func offered(_ indexes: Int...) -> [Bool] {
        var symbols = Array(repeating: false, count: 11)
        for index in indexes { symbols[index] = true }
        return symbols
    }

    private func scan(_ input: String, at offset: Int = 0, symbols: [Bool]) -> (Int, Int, Int)? {
        var scanner = RustExternalScanner()
        var lexer = StringScannerLexer(input, at: offset)
        guard scanner.scan(&lexer, validSymbols: symbols) else { return nil }
        return (lexer.resultSymbol, lexer.tokenStart, lexer.tokenEnd)
    }

    @Test
    func `externals follow grammar order and Rust is registered`() {
        #expect(
            RustExternalScanner.externalNames == [
                "string_content", "string_close", "_raw_string_literal_start", "raw_string_literal_content",
                "_raw_string_literal_end", "float_literal", "_outer_block_doc_comment_marker",
                "_inner_block_doc_comment_marker", "_block_comment_content", "_line_doc_content",
                "_error_sentinel"
            ])
        #expect(BundledScanners.byGrammarName["rust"] != nil)
    }

    // Reduced from upstream test/corpus/literals.txt string literals.
    @Test
    func `string content stops before an escape or closing quote`() {
        #expect(scan("hello\\n\"", symbols: offered(0))?.2 == 5)
        #expect(scan("hello\"", symbols: offered(0))?.2 == 5)
        #expect(scan("\"", symbols: offered(0)) == nil)
        #expect(scan("\\n", symbols: offered(0)) == nil)
        #expect(scan("unfinished", symbols: offered(0)) == nil)
    }

    @Test
    func `string closing quote is offered and content can fall through to it`() {
        #expect(scan("\"", symbols: offered(0, 1))?.0 == 1)
        #expect(scan("\"", symbols: offered(0, 1))?.2 == 1)
        #expect(scan("x", symbols: offered(1)) == nil)
        #expect(scan("\\\"", symbols: offered(0, 1)) == nil)
    }

    // Reduced from upstream test/corpus/literals.txt raw string and raw byte string literals.
    @Test(arguments: [
        ("r\"abc\"", 2), ("r#\"abc\"#", 3), ("br##\"abc\"##", 5),
        ("cr######\"abc\"######", 9)
    ])
    func `raw strings scan start content and end with matching hashes`(input: String, start: Int) {
        var scanner = RustExternalScanner()
        var opening = StringScannerLexer(input)
        #expect(scanner.scan(&opening, validSymbols: offered(2)))
        #expect(opening.resultSymbol == 2)
        #expect(opening.tokenEnd == start)
        var content = StringScannerLexer(input, at: start)
        #expect(scanner.scan(&content, validSymbols: offered(3)))
        #expect(content.resultSymbol == 3)
        #expect(content.tokenEnd == start + 3)
        var closing = StringScannerLexer(input, at: content.tokenEnd)
        #expect(scanner.scan(&closing, validSymbols: offered(4)))
        #expect(closing.resultSymbol == 4)
        #expect(closing.tokenEnd == input.utf8.count)
    }

    @Test
    func `raw delimiters reject malformed starts and unterminated content`() {
        #expect(scan("r#abc", symbols: offered(2)) == nil)
        #expect(scan("b\"abc\"", symbols: offered(2)) == nil)
        var scanner = RustExternalScanner()
        var opening = StringScannerLexer("r#\"abc\"")
        #expect(scanner.scan(&opening, validSymbols: offered(2)))
        var unterminated = StringScannerLexer("r#\"abc\"", at: opening.tokenEnd)
        #expect(!scanner.scan(&unterminated, validSymbols: offered(3)))
        #expect(scan("abc", symbols: offered(4)) == nil)
    }

    @Test
    func `raw strings retain the maximum hash count in serialized state`() {
        let hashes = String(repeating: "#", count: 255)
        let input = "r\(hashes)\"x\"\(hashes)"
        var scanner = RustExternalScanner()
        var opening = StringScannerLexer(input)
        #expect(scanner.scan(&opening, validSymbols: offered(2)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [255])
        var content = StringScannerLexer(input, at: opening.tokenEnd)
        #expect(scanner.scan(&content, validSymbols: offered(3)))
        var closing = StringScannerLexer(input, at: content.tokenEnd)
        #expect(scanner.scan(&closing, validSymbols: offered(4)))
        #expect(closing.tokenEnd == input.utf8.count)
    }

    // Reduced from upstream test/corpus/literals.txt floating point literals.
    @Test(arguments: [("123.123", 7), ("2.", 2), ("123.0f64", 8), ("12E+99_f64", 10)])
    func `float literals include fractions exponents and suffixes`(input: String, end: Int) {
        #expect(scan(input, symbols: offered(5))?.0 == 5)
        #expect(scan(input, symbols: offered(5))?.2 == end)
    }

    // Reduced from upstream test/corpus/expressions.txt range and field expressions.
    @Test(arguments: ["1..2", "1.max(2)", "1.0.0", "1", "0.1.2"])
    func `ranges and methods are not floats and adjacent floats keep their boundary`(input: String) {
        if input == "1.0.0" || input == "0.1.2" {
            #expect(scan(input, symbols: offered(5))?.2 == 3)
        } else {
            #expect(scan(input, symbols: offered(5)) == nil)
        }
    }

    @Test
    func `tuple field indexes rely on the grammar to withhold float literals`() {
        #expect(scan("value.0.1.iter()", at: 6, symbols: offered(5))?.2 == 9)
        #expect(scan("value.0.1.iter()", at: 6, symbols: offered(2)) == nil)
    }

    // Reduced from upstream test/corpus/source_files.txt block doc comments.
    @Test
    func `outer and inner block doc markers require their exact prefix`() {
        #expect(scan("* Outer block comment */", symbols: offered(6))?.0 == 6)
        #expect(scan("! Inner block comment */", symbols: offered(7))?.0 == 7)
        #expect(scan("*/", symbols: offered(6)) == nil)
        #expect(scan("** only a comment", symbols: offered(6)) == nil)
        #expect(scan("x", symbols: offered(7)) == nil)
    }

    @Test
    func `block content tracks nested comments and stops before closing slash`() {
        let input = " body /* nested */ outer */"
        #expect(scan(input, symbols: offered(8))?.0 == 8)
        #expect(scan(input, symbols: offered(8))?.2 == input.utf8.count - 2)
        #expect(scan("*/", symbols: offered(8)) == nil)
        #expect(scan("", symbols: offered(8))?.0 == 8)
        #expect(scan("", symbols: offered(8))?.2 == 0)
    }

    // Reduced from upstream test/corpus/source_files.txt line doc comments.
    @Test(arguments: ["/// Outer line doc comment\n", "//! Inner line doc comment\n"])
    func `line doc content includes newline`(input: String) {
        #expect(scan(input, at: 3, symbols: offered(9))?.2 == input.utf8.count)
        #expect(scan(input, at: 3, symbols: offered(9))?.0 == 9)
        #expect(scan("", symbols: offered(9))?.2 == 0)
        #expect(scan(input, at: 3, symbols: offered(1)) == nil)
    }

    @Test
    func `valid symbols gate tokens and error recovery emits no sentinel`() {
        #expect(scan("hello\"", symbols: offered(0, 5)) == nil)
        #expect(scan("1.25", symbols: offered(1)) == nil)
        #expect(scan("r#\"x\"#", symbols: offered(5)) == nil)
        #expect(scan("hello\"", symbols: Array(repeating: true, count: 11)) == nil)
        #expect(scan("anything", symbols: offered(10)) == nil)
    }

    @Test
    func `serialization round trip and empty state reset the raw delimiter`() {
        var scanner = RustExternalScanner()
        var opening = StringScannerLexer("r##\"x\"##")
        #expect(scanner.scan(&opening, validSymbols: offered(2)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [2])
        #expect(state.count <= maximumSerializedScannerStateSize)

        var restored = RustExternalScanner()
        restored.deserialize(state[...])
        var content = StringScannerLexer("x\"##")
        #expect(restored.scan(&content, validSymbols: offered(3)))
        #expect(content.tokenEnd == 1)
        var closing = StringScannerLexer("\"##")
        #expect(restored.scan(&closing, validSymbols: offered(4)))
        #expect(closing.tokenEnd == 3)

        restored.deserialize([])
        var reset: [UInt8] = []
        restored.serialize(into: &reset)
        #expect(reset == [0])
    }

    @Test
    func `declining a malformed raw start preserves delimiter state`() {
        var scanner = RustExternalScanner()
        scanner.deserialize([3][...])
        var lexer = StringScannerLexer("r##unfinished")
        #expect(!scanner.scan(&lexer, validSymbols: offered(2)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [3])
    }
}
