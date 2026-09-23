import AtelierParser
import Testing

@testable import AtelierScanners

struct KotlinExternalScannerTests {
    private let all = Array(repeating: true, count: 9)

    private func offered(_ indexes: Int...) -> [Bool] {
        var symbols = Array(repeating: false, count: 9)
        for index in indexes { symbols[index] = true }
        return symbols
    }

    private func scan(_ input: String, at offset: Int = 0, symbols: [Bool]) -> (Int, Int, Int)? {
        var scanner = KotlinExternalScanner()
        var lexer = StringScannerLexer(input, at: offset)
        guard scanner.scan(&lexer, validSymbols: symbols) else { return nil }
        return (lexer.resultSymbol, lexer.tokenStart, lexer.tokenEnd)
    }

    @Test
    func `external names follow the bundled grammar order`() {
        #expect(
            KotlinExternalScanner.externalNames == [
                "_automatic_semicolon", "_import_list_delimiter", "safe_nav", "multiline_comment",
                "_string_start", "_string_end", "string_content", "_primary_constructor_keyword", "_import_dot"
            ])
        #expect(BundledScanners.byGrammarName["kotlin"] != nil)
    }

    @Test(arguments: ["\nnext", "\r\nnext", ";", "\n+next", "\n-next", "\nvalue"])
    func `inserts automatic semicolons at statement breaks`(input: String) {
        #expect(scan(input, symbols: offered(0))?.0 == 0)
    }

    @Test(arguments: [
        "\n.name", "\n?.name", "\n* value", "\n/ value", "\n!= value", "\nelse", "\ncatch",
        "\nfinally", "\nas Type", "\nwhere T", " next", "\n// comment\n.name", "\n// comment\ncatch"
    ])
    func `does not insert semicolons before continuations`(input: String) {
        #expect(scan(input, symbols: offered(0)) == nil)
    }

    @Test
    func `parenthesized expressions do not offer automatic semicolons`() {
        #expect(scan("(a\n b)", at: 2, symbols: offered(2)) == nil)
    }

    @Test(arguments: ["", "\n\nfun main()", "\nfun main()"])
    func `ends import lists at EOF blank lines and declarations`(input: String) {
        #expect(scan(input, symbols: offered(1))?.0 == 1)
    }

    @Test(arguments: ["\nimport java.io.Path", " import java.io.Path", "x"])
    func `does not end import lists before another import or without a line break`(input: String) {
        #expect(scan(input, symbols: offered(1)) == nil)
    }

    @Test
    func `scans import dots and stops a malformed trailing dot before another import`() {
        #expect(scan(".util", symbols: offered(8))?.0 == 8)
        #expect(scan(".\nimport java.io.Path", symbols: offered(0, 8))?.0 == 0)
        #expect(scan("util", symbols: offered(8)) == nil)
    }

    @Test(arguments: ["?.bar()", "?\n.bar()", " ?  .bar()"])
    func `scans safe navigation across whitespace`(input: String) {
        #expect(scan(input, symbols: offered(2))?.0 == 2)
    }

    @Test(arguments: ["?name", "?\nname", ".name"])
    func `rejects incomplete safe navigation`(input: String) {
        #expect(scan(input, symbols: offered(2)) == nil)
    }

    @Test
    func `scans nested and unterminated block comments`() {
        let nested = "/* /* inner */ outer */"
        #expect(scan(nested, symbols: offered(3))?.2 == nested.utf8.count)
        #expect(scan("/* /* */ */", symbols: offered(3))?.0 == 3)
        #expect(scan("/* unterminated", symbols: offered(3))?.0 == 3)
        #expect(scan("/ value", symbols: offered(3)) == nil)
    }

    @Test(arguments: ["\"hello\"", "\"\"\"hello\"\"\""])
    func `scans both string delimiters and their content`(input: String) {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer(input)
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        #expect(start.resultSymbol == 4)
        var content = StringScannerLexer(input, at: start.tokenEnd)
        #expect(scanner.scan(&content, validSymbols: offered(6)))
        #expect(content.resultSymbol == 6)
        var end = StringScannerLexer(input, at: content.tokenEnd)
        #expect(scanner.scan(&end, validSymbols: offered(5, 6)))
        #expect(end.resultSymbol == 5)
        #expect(end.tokenEnd == input.utf8.count)
    }

    @Test
    func `rejects string tokens outside a string`() {
        #expect(scan("'hello'", symbols: offered(4)) == nil)
        #expect(scan("hello", symbols: offered(6)) == nil)
        #expect(scan("\"", symbols: offered(5)) == nil)
    }

    @Test(arguments: ["$name", "${value}"])
    func `leaves interpolations to the grammar`(template: String) {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer("\"\(template)\"")
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        var content = StringScannerLexer("\"\(template)\"", at: start.tokenEnd)
        #expect(!scanner.scan(&content, validSymbols: offered(6)))
    }

    @Test
    func `keeps escaped dollar signs in string content`() {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer("\"\\$name\"")
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        var content = StringScannerLexer("\"\\$name\"", at: start.tokenEnd)
        #expect(scanner.scan(&content, validSymbols: offered(6)))
        #expect(content.resultSymbol == 6)
    }

    @Test
    func `Unicode letters start string interpolations`() {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer("\"$λ\"")
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        var content = StringScannerLexer("\"$λ\"", at: start.tokenEnd)
        #expect(!scanner.scan(&content, validSymbols: offered(6)))
    }

    @Test
    func `scans the primary constructor keyword at either line position`() {
        #expect(scan("constructor()", symbols: offered(7))?.0 == 7)
        var symbols = offered(0)
        symbols[7] = true
        #expect(scan("\nconstructor()", symbols: symbols)?.0 == 7)
        #expect(scan("constructorName", symbols: offered(7)) == nil)
        #expect(scan("constructoré", symbols: offered(7)) == nil)
    }

    @Test
    func `does not produce a token that is not offered`() {
        #expect(scan("/* block */", symbols: offered(2)) == nil)
        #expect(scan("?.name", symbols: offered(3)) == nil)
        #expect(scan("\"text\"", symbols: offered(8)) == nil)
        #expect(scan(".\nimport java.io.Path", symbols: offered(8)) == nil)
        #expect(scan("\n/* comment */.next", symbols: offered(0)) == nil)
    }

    @Test
    func `an unoffered string end leaves the delimiter stack intact`() {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer("\"\"")
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        var unofferedEnd = StringScannerLexer("\"")
        #expect(!scanner.scan(&unofferedEnd, validSymbols: offered(6)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [UInt8(ascii: "\"")])
        var offeredEnd = StringScannerLexer("\"")
        #expect(scanner.scan(&offeredEnd, validSymbols: offered(5, 6)))
        #expect(offeredEnd.resultSymbol == 5)
    }

    @Test
    func `all symbols valid follows C scanner recovery precedence`() {
        #expect(scan("constructor()", symbols: all) == nil)
        #expect(scan("\nconstructor()", symbols: all)?.0 == 0)
        #expect(scan("/* comment */", symbols: all) == nil)
    }

    @Test
    func `serialized string state round trips and empty state resets it`() {
        var scanner = KotlinExternalScanner()
        var start = StringScannerLexer("\"\"\"hello\"\"\"")
        #expect(scanner.scan(&start, validSymbols: offered(4)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = KotlinExternalScanner()
        restored.deserialize(state[...])
        var content = StringScannerLexer("hello\"\"\"")
        #expect(restored.scan(&content, validSymbols: offered(6)))
        #expect(content.resultSymbol == 6)
        restored.deserialize([][...])
        var afterReset = StringScannerLexer("hello\"\"\"")
        #expect(!restored.scan(&afterReset, validSymbols: offered(6)))
    }

    @Test
    func `open delimiter state never exceeds the parser serialization limit`() {
        var scanner = KotlinExternalScanner()
        for _ in 0 ..< maximumSerializedScannerStateSize {
            var lexer = StringScannerLexer("\"")
            #expect(scanner.scan(&lexer, validSymbols: offered(4)))
        }
        var overflow = StringScannerLexer("\"")
        #expect(!scanner.scan(&overflow, validSymbols: offered(4)))
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == maximumSerializedScannerStateSize)
        scanner.deserialize(Array(repeating: UInt8(ascii: "\""), count: maximumSerializedScannerStateSize + 1)[...])
        state.removeAll()
        scanner.serialize(into: &state)
        #expect(state.count == maximumSerializedScannerStateSize)
    }

    @Test
    func `scanner copies keep independent delimiter stacks`() {
        var first = KotlinExternalScanner()
        var start = StringScannerLexer("\"\"")
        #expect(first.scan(&start, validSymbols: offered(4)))
        var second = first
        var firstEnd = StringScannerLexer("\"")
        #expect(first.scan(&firstEnd, validSymbols: offered(5, 6)))
        #expect(firstEnd.resultSymbol == 5)
        var secondEnd = StringScannerLexer("\"")
        #expect(second.scan(&secondEnd, validSymbols: offered(5, 6)))
        #expect(secondEnd.resultSymbol == 5)
    }
}
