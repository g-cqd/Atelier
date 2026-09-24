import AtelierParser
import Testing

@testable import AtelierScanners

struct TOMLExternalScannerTests {
    private func scan(_ input: String, allowing names: [String]) -> (String?, StringScannerLexer) {
        var scanner = TOMLExternalScanner()
        var lexer = StringScannerLexer(input)
        let valid = TOMLExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? TOMLExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `externals match the bundled grammar and registry`() {
        #expect(
            TOMLExternalScanner.externalNames == [
                "_line_ending_or_eof", "_multiline_basic_string_content", "_multiline_basic_string_end",
                "_multiline_literal_string_content", "_multiline_literal_string_end"
            ])
        #expect(BundledScanners.byGrammarName["toml"] != nil)
    }

    @Test(arguments: ["", "   ", "\nnext", " \t\nnext", "\r\nnext"])
    func `value may end at a line ending or end of input`(_ input: String) {
        #expect(scan(input, allowing: ["_line_ending_or_eof"]).0 == "_line_ending_or_eof")
    }

    @Test(arguments: [" next", "\rnext", "# comment", ";next"])
    func `line ending rejects a continued value`(_ input: String) {
        #expect(scan(input, allowing: ["_line_ending_or_eof"]).0 == nil)
    }

    @Test(arguments: [
        ("\"", "_multiline_basic_string_content", "_multiline_basic_string_end"),
        ("'", "_multiline_literal_string_content", "_multiline_literal_string_end")
    ])
    func `one or two quotes are content and three quotes end a multiline string`(
        _ quote: String, _ contentName: String, _ endName: String
    ) {
        for count in 1 ... 2 {
            let input = String(repeating: quote, count: count) + "x"
            let (name, lexer) = scan(input, allowing: [contentName, endName])
            #expect(name == contentName)
            #expect(lexer.tokenEnd == count)
        }
        let (name, lexer) = scan(String(repeating: quote, count: 3) + "x", allowing: [contentName, endName])
        #expect(name == endName)
        #expect(lexer.tokenEnd == 3)
        let four = scan(String(repeating: quote, count: 4), allowing: [contentName, endName])
        #expect(four.0 == contentName)
        #expect(four.1.tokenEnd == 1)
    }

    @Test
    func `only offered symbols may be produced`() {
        #expect(scan("\"\"\"", allowing: []).0 == nil)
        #expect(scan("\"", allowing: ["_multiline_basic_string_content"]).0 == nil)
        #expect(scan("\"", allowing: ["_multiline_basic_string_end"]).0 == nil)
        #expect(scan("\"", allowing: ["_line_ending_or_eof", "_multiline_basic_string_end"]).0 == nil)
        #expect(scan("'", allowing: ["_multiline_literal_string_end"]).0 == nil)
        #expect(scan("\n", allowing: ["_multiline_basic_string_end"]).0 == nil)
    }

    @Test
    func `stateless serialization round trip and empty restore`() {
        var scanner = TOMLExternalScanner()
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.isEmpty)
        #expect(state.count <= maximumSerializedScannerStateSize)
        scanner.deserialize([1, 2][...])
        scanner.deserialize([])
        #expect(scan("\r\n", allowing: ["_line_ending_or_eof"]).0 == "_line_ending_or_eof")
    }
}
