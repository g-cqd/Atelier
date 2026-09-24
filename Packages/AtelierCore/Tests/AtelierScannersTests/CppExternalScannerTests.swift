import AtelierParser
import Testing

@testable import AtelierScanners

struct CppExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, allowing names: [String], scanner: inout CppExternalScanner
    ) -> (String?, StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = CppExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? CppExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `externals match the bundled grammar and registry`() {
        #expect(CppExternalScanner.externalNames == ["raw_string_delimiter", "raw_string_content"])
        #expect(BundledScanners.byGrammarName["cpp"] != nil)
    }

    @Test(arguments: ["tag", "abc_123", "0123456789abcde"])
    func `opening and closing raw string delimiters match`(_ delimiter: String) {
        var scanner = CppExternalScanner()
        let open = scan(delimiter + "(body)", allowing: ["raw_string_delimiter"], scanner: &scanner)
        #expect(open.0 == "raw_string_delimiter")
        #expect(open.1.tokenEnd == delimiter.utf8.count)
        let content = scan("body)" + delimiter + "\"", allowing: ["raw_string_content"], scanner: &scanner)
        #expect(content.0 == "raw_string_content")
        #expect(content.1.tokenEnd == 4)
        let close = scan(delimiter + "\"", allowing: ["raw_string_delimiter"], scanner: &scanner)
        #expect(close.0 == "raw_string_delimiter")
        #expect(close.1.tokenEnd == delimiter.utf8.count)
    }

    @Test
    func `empty delimiter uses the grammar fallback and content still stops at closing quote`() {
        var scanner = CppExternalScanner()
        #expect(scan("(body)\"", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == nil)
        let content = scan("body)\"", allowing: ["raw_string_content"], scanner: &scanner)
        #expect(content.0 == "raw_string_content")
        #expect(content.1.tokenEnd == 4)
    }

    @Test(arguments: ["FOO", ""])
    func `raw string corpus literal scans at each external boundary`(_ delimiter: String) {
        let literal = "R\"" + delimiter + "(body)" + delimiter + "\""
        var scanner = CppExternalScanner()
        let open = scan(literal, at: 2, allowing: ["raw_string_delimiter"], scanner: &scanner)
        #expect(open.0 == (delimiter.isEmpty ? nil : "raw_string_delimiter"))
        let contentOffset = 3 + delimiter.utf8.count
        let content = scan(literal, at: contentOffset, allowing: ["raw_string_content"], scanner: &scanner)
        #expect(content.0 == "raw_string_content")
        #expect(content.1.tokenEnd == contentOffset + 4)
        if !delimiter.isEmpty {
            let close = scan(literal, at: contentOffset + 5, allowing: ["raw_string_delimiter"], scanner: &scanner)
            #expect(close.0 == "raw_string_delimiter")
            #expect(close.1.tokenEnd == contentOffset + 5 + delimiter.utf8.count)
        }
    }

    @Test
    func `false closing sequence remains inside content`() {
        var scanner = CppExternalScanner()
        #expect(scan("tag(", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == "raw_string_delimiter")
        let content = scan("a)tagX b)taY c)tag\"", allowing: ["raw_string_content"], scanner: &scanner)
        #expect(content.0 == "raw_string_content")
        #expect(content.1.tokenEnd == "a)tagX b)taY c".utf8.count)
    }

    @Test
    func `invalid delimiter and unoffered tokens leave state unchanged`() {
        var scanner = CppExternalScanner()
        for input in ["bad delimiter(", "bad\\delimiter(", "0123456789abcdef("] {
            #expect(scan(input, allowing: ["raw_string_delimiter"], scanner: &scanner).0 == nil)
            var state: [UInt8] = []
            scanner.serialize(into: &state)
            #expect(state.isEmpty)
        }
        #expect(scan("tag(", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("tag(", allowing: CppExternalScanner.externalNames, scanner: &scanner).0 == nil)
        #expect(scan("body)\"", allowing: [], scanner: &scanner).0 == nil)
        #expect(scan("tag(", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == "raw_string_delimiter")
        #expect(scan("wrong\"", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == nil)
        #expect(scan("tag\"", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == "raw_string_delimiter")
    }

    @Test
    func `serialization restores delimiter and empty state resets it`() {
        var scanner = CppExternalScanner()
        #expect(scan("tag(", allowing: ["raw_string_delimiter"], scanner: &scanner).0 == "raw_string_delimiter")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == 3 * MemoryLayout<UInt32>.size)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = CppExternalScanner()
        restored.deserialize(state[...])
        #expect(scan("tag\"", allowing: ["raw_string_delimiter"], scanner: &restored).0 == "raw_string_delimiter")
        restored.deserialize(state[...])
        restored.deserialize([])
        #expect(scan("tag\"", allowing: ["raw_string_delimiter"], scanner: &restored).0 == nil)
    }
}
