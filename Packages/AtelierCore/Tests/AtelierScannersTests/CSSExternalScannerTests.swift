import AtelierParser
import Testing

@testable import AtelierScanners

struct CSSExternalScannerTests {
    private func scan(_ input: String, allowing names: [String]) -> (String?, StringScannerLexer) {
        var scanner = CSSExternalScanner()
        var lexer = StringScannerLexer(input)
        let valid = CSSExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? CSSExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `externals match the bundled grammar and registry`() {
        #expect(
            CSSExternalScanner.externalNames == [
                "_descendant_operator", "_pseudo_class_selector_colon", "__error_recovery"
            ])
        #expect(BundledScanners.byGrammarName["css"] != nil)
    }

    @Test(arguments: [" div", "\t.class", "\n#id", " [role]", " *", " -custom", " élement"])
    func `whitespace before a selector is a descendant operator`(_ input: String) {
        let (name, lexer) = scan(input, allowing: ["_descendant_operator"])
        #expect(name == "_descendant_operator")
        #expect(lexer.tokenEnd == 1 || lexer.tokenEnd == 2)
    }

    @Test(arguments: [" {", " > div", " + div", " ~ div", " ;", " "])
    func `whitespace before a block or combinator is not a descendant operator`(_ input: String) {
        #expect(scan(input, allowing: ["_descendant_operator"]).0 == nil)
    }

    @Test
    func `pseudo class colon needs a selector block and ignores braces in comments`() {
        #expect(
            scan(":hover { color: red; }", allowing: ["_pseudo_class_selector_colon"]).0
                == "_pseudo_class_selector_colon")
        #expect(scan(":not(.x) { }", allowing: ["_pseudo_class_selector_colon"]).1.tokenEnd == 1)
        #expect(scan(": red;", allowing: ["_pseudo_class_selector_colon"]).0 == nil)
        #expect(scan("::before { }", allowing: ["_pseudo_class_selector_colon"]).0 == nil)
        #expect(scan(":value /* { */ ;", allowing: ["_pseudo_class_selector_colon"]).0 == nil)
        #expect(scan(":incomplete", allowing: ["_pseudo_class_selector_colon"]).0 == "_pseudo_class_selector_colon")
    }

    @Test
    func `error recovery and valid symbols gate every result`() {
        #expect(scan(" div", allowing: []).0 == nil)
        #expect(scan(":hover {", allowing: []).0 == nil)
        #expect(scan(" div", allowing: CSSExternalScanner.externalNames).0 == nil)
        #expect(scan(":hover {", allowing: ["_pseudo_class_selector_colon", "__error_recovery"]).0 == nil)
        #expect(scan("", allowing: ["__error_recovery"]).0 == nil)
    }

    @Test
    func `stateless serialization and empty restore preserve behavior`() {
        var scanner = CSSExternalScanner()
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.isEmpty)
        #expect(state.count <= maximumSerializedScannerStateSize)
        scanner.deserialize([1, 2][...])
        scanner.deserialize([])
        #expect(scan(" a", allowing: ["_descendant_operator"]).0 == "_descendant_operator")
    }
}
