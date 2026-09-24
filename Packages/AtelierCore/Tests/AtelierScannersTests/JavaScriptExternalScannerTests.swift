import AtelierParser
import Testing

@testable import AtelierScanners

struct JavaScriptExternalScannerTests {
    private func scan(_ input: String, allowing names: [String]) -> (String?, StringScannerLexer) {
        var scanner = JavaScriptExternalScanner()
        var lexer = StringScannerLexer(input)
        let valid = JavaScriptExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? JavaScriptExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `names match the bundled grammar and the scanner is registered`() {
        #expect(
            JavaScriptExternalScanner.externalNames == [
                "_automatic_semicolon", "_template_chars", "_ternary_qmark", "html_comment", "||",
                "escape_sequence", "regex_pattern", "jsx_text"
            ])
        #expect(BundledScanners.byGrammarName["javascript"] != nil)
    }

    // Inputs are reduced from upstream test/corpus/semicolon_insertion.txt and expressions.txt.
    @Test(arguments: ["\nnext", "\n++b", "}", ""])
    func `inserts an automatic semicolon at a statement boundary`(_ input: String) {
        let (name, lexer) = scan(input, allowing: ["_automatic_semicolon", "||"])
        #expect(name == "_automatic_semicolon")
        #expect(lexer.tokenEnd == 0)
    }

    @Test(arguments: ["\n(", "\n[", "\n`x`", "\n.foo", "\n?.foo", "\n+foo", "\n||foo", " foo", "++foo"])
    func `does not insert a semicolon into an expression continuation`(_ input: String) {
        #expect(scan(input, allowing: ["_automatic_semicolon", "||"]).0 == nil)
    }

    @Test
    func `comment context flag controls insertion and division rejects it`() {
        #expect(scan("// comment\nnext", allowing: ["_automatic_semicolon"]).0 == "_automatic_semicolon")
        #expect(scan("/*\n*/next", allowing: ["_automatic_semicolon"]).0 == "_automatic_semicolon")
        #expect(scan("/*\n*/\nnext", allowing: ["_automatic_semicolon"]).0 == "_automatic_semicolon")
        #expect(scan("/* comment */next", allowing: ["_automatic_semicolon"]).0 == nil)
        #expect(scan("/* comment */next", allowing: ["_automatic_semicolon", "||"]).0 == nil)
        #expect(scan("/value", allowing: ["_automatic_semicolon"]).0 == nil)
    }

    @Test
    func `line separators and statement offsets follow JavaScript insertion rules`() {
        #expect(scan("\u{2028}next", allowing: ["_automatic_semicolon", "||"]).0 == "_automatic_semicolon")
        for (input, offset) in [("return value", 6), ("i++ +value", 3)] {
            var scanner = JavaScriptExternalScanner()
            var lexer = StringScannerLexer(input, at: offset)
            let valid = JavaScriptExternalScanner.externalNames.map { $0 == "_automatic_semicolon" }
            #expect(!scanner.scan(&lexer, validSymbols: valid))
        }
    }

    @Test(arguments: ["hello${name}", "hello`"])
    func `template characters stop before interpolation or closing backtick`(_ input: String) {
        let (name, lexer) = scan(input, allowing: ["_template_chars"])
        #expect(name == "_template_chars")
        #expect(lexer.tokenEnd == 5)
    }

    @Test(arguments: ["${name}", "`", "\\escape"])
    func `empty template characters do not form a token`(_ input: String) {
        #expect(scan(input, allowing: ["_template_chars"]).0 == nil)
    }

    @Test(arguments: ["? a : b", "?.5"])
    func `scans a ternary question mark`(_ input: String) {
        let (name, lexer) = scan(input, allowing: ["_ternary_qmark"])
        #expect(name == "_ternary_qmark")
        #expect(lexer.tokenEnd == 1)
    }

    @Test(arguments: ["?.name", "??value", "value / next"])
    func `optional chaining and coalescing are not ternary marks`(_ input: String) {
        #expect(scan(input, allowing: ["_ternary_qmark"]).0 == nil)
    }

    @Test(arguments: ["<!-- comment\nnext", "--> comment\nnext"])
    func `scans HTML comments through the end of their line`(_ input: String) {
        let (name, lexer) = scan(input, allowing: ["html_comment"])
        #expect(name == "html_comment")
        #expect(lexer.tokenEnd == "<!-- comment".utf8.count || lexer.tokenEnd == "--> comment".utf8.count)
    }

    @Test(arguments: ["<! comment", "-- comment", "<div>"])
    func `incomplete HTML markers are rejected`(_ input: String) {
        #expect(scan(input, allowing: ["html_comment"]).0 == nil)
    }

    @Test
    func `logical or escape and regex validity suppresses HTML scanning`() {
        for flag in ["||", "escape_sequence", "regex_pattern"] {
            #expect(scan("<!-- comment", allowing: ["html_comment", flag]).0 == nil)
        }
        #expect(scan("/pattern/", allowing: ["regex_pattern"]).0 == nil)
        #expect(scan("\\n", allowing: ["escape_sequence"]).0 == nil)
        #expect(scan("||", allowing: ["||"]).0 == nil)
    }

    @Test
    func `JSX text stops at markup and rejects newline indentation`() {
        let (name, lexer) = scan("hello <tag>", allowing: ["jsx_text"])
        #expect(name == "jsx_text")
        #expect(lexer.tokenEnd == 6)
        #expect(scan("\n  <tag>", allowing: ["jsx_text"]).0 == nil)
        #expect(scan("<tag>", allowing: ["jsx_text"]).0 == nil)
    }

    @Test
    func `valid symbols gate results and all symbols trigger recovery rejection`() {
        #expect(scan("\nnext", allowing: []).0 == nil)
        #expect(scan("text${x}", allowing: ["_template_chars", "_automatic_semicolon"]).0 == nil)
        #expect(scan("\nnext", allowing: JavaScriptExternalScanner.externalNames).0 == nil)
    }

    @Test
    func `state serialization is empty and deserialization resets the scanner`() {
        var scanner = JavaScriptExternalScanner()
        var bytes: [UInt8] = []
        scanner.serialize(into: &bytes)
        #expect(bytes.isEmpty)
        scanner.deserialize([1, 2, 3][...])
        scanner.deserialize([])
        var lexer = StringScannerLexer("? yes : no")
        #expect(scanner.scan(&lexer, validSymbols: [false, false, true, false, false, false, false, false]))
        #expect(lexer.resultSymbol == 2)
    }
}
