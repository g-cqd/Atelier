import AtelierParser
import Testing

@testable import AtelierScanners

struct HTMLExternalScannerTests {
    private func scan(
        _ input: String, allowing names: [String], scanner: inout HTMLExternalScanner
    ) -> (String?, StringScannerLexer) {
        var lexer = StringScannerLexer(input)
        let valid = HTMLExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? HTMLExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `externals match the bundled grammar and registry`() {
        #expect(
            HTMLExternalScanner.externalNames == [
                "_start_tag_name", "_script_start_tag_name", "_style_start_tag_name", "_end_tag_name",
                "erroneous_end_tag_name", "/>", "_implicit_end_tag", "raw_text", "comment"
            ])
        #expect(BundledScanners.byGrammarName["html"] != nil)
    }

    @Test(arguments: ["div", "my-component", "svg:path"])
    func `start and matching end names use the open tag stack`(_ name: String) {
        var scanner = HTMLExternalScanner()
        #expect(scan(name + ">", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan(name.uppercased() + ">", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == 4)
    }

    @Test
    func `Unicode alphanumeric tag names match after uppercase mapping`() {
        var scanner = HTMLExternalScanner()
        let start = scan("é>", allowing: ["_start_tag_name"], scanner: &scanner)
        #expect(start.0 == "_start_tag_name")
        #expect(start.1.tokenEnd == 2)
        #expect(scan("É>", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
    }

    @Test(arguments: [
        ("script", "_script_start_tag_name", "let x = 1;</SCRIPT>"),
        ("style", "_style_start_tag_name", "a { color: red }</StYlE>")
    ])
    func `script and style raw text stop before matching end tags`(
        _ tag: String, _ token: String, _ body: String
    ) {
        var scanner = HTMLExternalScanner()
        #expect(scan(tag + ">", allowing: ["_start_tag_name", token], scanner: &scanner).0 == token)
        let (name, lexer) = scan(body, allowing: ["raw_text"], scanner: &scanner)
        #expect(name == "raw_text")
        #expect(lexer.tokenEnd == body.prefix(while: { $0 != "<" }).utf8.count)
        #expect(scan(tag + ">", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
    }

    @Test
    func `self closing delimiter pops its open tag`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("/>", allowing: ["/>"], scanner: &scanner).0 == nil)
        #expect(scan("img", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("/>", allowing: ["/>"], scanner: &scanner).0 == "/>")
        #expect(
            scan("img", allowing: ["_end_tag_name", "erroneous_end_tag_name"], scanner: &scanner).0
                == "erroneous_end_tag_name")
        #expect(scan("/x", allowing: ["/>"], scanner: &scanner).0 == nil)
    }

    @Test
    func `void and optional tags close implicitly`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("br", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("<div", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
        #expect(scan("p", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("<div", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
        #expect(scan("li", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("<li", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
    }

    @Test
    func `end tag can close an ancestor through queued implicit ends`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("div", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("span", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("</div>", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
        #expect(scan("div", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
    }

    @Test(arguments: ["p", "li"])
    func `closing optional tags implicitly ends their nested child`(_ tag: String) {
        var scanner = HTMLExternalScanner()
        #expect(scan(tag, allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("span", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("</" + tag + ">", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
        #expect(scan(tag, allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
    }

    @Test
    func `wrong end tag is erroneous and does not pop the stack`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("div", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(
            scan("span", allowing: ["_end_tag_name", "erroneous_end_tag_name"], scanner: &scanner).0
                == "erroneous_end_tag_name")
        #expect(scan("div", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
    }

    @Test
    func `comment consumes through its first double dash close`() {
        var scanner = HTMLExternalScanner()
        let (name, lexer) = scan("<!-- a -- > b -->tail", allowing: ["comment"], scanner: &scanner)
        #expect(name == "comment")
        #expect(lexer.tokenEnd == "<!-- a -- > b -->".utf8.count)
        #expect(scan("<!-- unfinished", allowing: ["comment"], scanner: &scanner).0 == nil)
    }

    @Test
    func `unoffered tokens and failed probes preserve the stack`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("div", allowing: HTMLExternalScanner.externalNames, scanner: &scanner).0 == nil)
        #expect(scan("script", allowing: ["_start_tag_name"], scanner: &scanner).0 == nil)
        #expect(scan("style", allowing: ["_start_tag_name"], scanner: &scanner).0 == nil)
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0, 0, 0])
        #expect(scan("div", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("/>", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("span", allowing: ["_end_tag_name"], scanner: &scanner).0 == nil)
        #expect(scan("div", allowing: ["_end_tag_name"], scanner: &scanner).0 == "_end_tag_name")
        #expect(scan("<!-- x -->", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("div", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("text", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("br", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("<div", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("<div", allowing: ["_implicit_end_tag"], scanner: &scanner).0 == "_implicit_end_tag")
    }

    @Test
    func `serialization restores tags and empty state clears them`() {
        var scanner = HTMLExternalScanner()
        #expect(scan("div", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        #expect(scan("my-widget", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = HTMLExternalScanner()
        restored.deserialize(state[...])
        #expect(scan("my-widget", allowing: ["_end_tag_name"], scanner: &restored).0 == "_end_tag_name")
        restored.deserialize(state[...])
        restored.deserialize([])
        #expect(
            scan("my-widget", allowing: ["_end_tag_name", "erroneous_end_tag_name"], scanner: &restored).0
                == "erroneous_end_tag_name")
    }

    @Test
    func `deep tag stacks serialize within the byte limit`() {
        var scanner = HTMLExternalScanner()
        for _ in 0 ..< 1_200 {
            #expect(scan("div", allowing: ["_start_tag_name"], scanner: &scanner).0 == "_start_tag_name")
        }
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = HTMLExternalScanner()
        restored.deserialize(state[...])
        var roundTrip: [UInt8] = []
        restored.serialize(into: &roundTrip)
        #expect(roundTrip == state)
    }
}
