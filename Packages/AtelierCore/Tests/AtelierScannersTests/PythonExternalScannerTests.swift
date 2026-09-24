import AtelierParser
import Foundation
import Testing

@testable import AtelierScanners

struct PythonCase: Sendable {
    let name: String
    let input: String
    let rejected: String
    let offered: [String]

    init(_ name: String, _ input: String, rejecting rejected: String, offering offered: [String]? = nil) {
        self.name = name
        self.input = input
        self.rejected = rejected
        self.offered = offered ?? [name]
    }
}

private let directCases: [PythonCase] = [
    .init("_newline", "\nvalue", rejecting: "value"),
    .init("_indent", "\n    value", rejecting: "\nvalue"),
    .init("_dedent", "\nvalue", rejecting: "\n    value"),
    .init("string_start", "fr\"text", rejecting: "frvalue"),
    .init("_string_content", "text\"", rejecting: "\""),
    .init("escape_interpolation", "{{", rejecting: "{x"),
    .init("string_end", "\"", rejecting: "text", offering: ["_string_content", "string_end"])
]

struct PythonExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, offering names: [String], scanner: inout PythonExternalScanner
    ) -> (name: String?, lexer: StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = PythonExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? PythonExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    /// Opt-in scan timing over a four-kilobyte indentation line; run with `GDV_BENCH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `measure indentation scan throughput`() {
        let template = StringScannerLexer("\n" + String(repeating: " ", count: 4096) + "pass")
        let valid = PythonExternalScanner.externalNames.map { $0 == "_indent" }
        let rounds = 1_000
        let clock = ContinuousClock()
        let start = clock.now
        var recognized = 0
        for _ in 0 ..< rounds {
            var scanner = PythonExternalScanner()
            var lexer = template
            if scanner.scan(&lexer, validSymbols: valid) { recognized += 1 }
        }
        let elapsed = clock.now - start
        #expect(recognized == rounds)
        print("BENCH python indent 4 KiB x \(rounds): \(elapsed)")
    }

    @Test
    func `external names match the bundled grammar and registry`() {
        #expect(
            PythonExternalScanner.externalNames == [
                "_newline", "_indent", "_dedent", "string_start", "_string_content", "escape_interpolation",
                "string_end", "comment", "]", ")", "}", "except"
            ])
        #expect(BundledScanners.byGrammarName["python"] != nil)
    }

    @Test(arguments: directCases)
    func `each emitted token has a positive and negative input`(_ testCase: PythonCase) {
        var scanner = PythonExternalScanner()
        if testCase.name == "_dedent" {
            #expect(scan("\n    value", offering: ["_indent"], scanner: &scanner).name == "_indent")
        } else if testCase.name == "_string_content" || testCase.name == "string_end" {
            #expect(scan("\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        } else if testCase.name == "escape_interpolation" {
            #expect(scan("f\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        }
        let positive = scan(testCase.input, offering: testCase.offered, scanner: &scanner)
        #expect(positive.name == testCase.name)
        scanner = PythonExternalScanner()
        if testCase.name == "_dedent" {
            #expect(scan("\n    value", offering: ["_indent"], scanner: &scanner).name == "_indent")
        } else if testCase.name == "_string_content" || testCase.name == "string_end" {
            #expect(scan("\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        } else if testCase.name == "escape_interpolation" {
            #expect(scan("f\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        }
        #expect(scan(testCase.rejected, offering: testCase.offered, scanner: &scanner).name != testCase.name)
    }

    @Test(arguments: [
        "r\"", "R'", "b\"", "B'", "u\"", "U'", "f\"", "F'", "fr\"", "rf'", "rb\"", "br'", "t\"", "T'", "'''", "\"\"\"",
        "`"
    ])
    func `corpus string prefixes and quotes open a delimiter`(_ input: String) {
        var scanner = PythonExternalScanner()
        #expect(scan(input, offering: ["string_start"], scanner: &scanner).name == "string_start")
        #expect(scanner.delimiters.count == 1)
    }

    @Test(arguments: ["frword", "rbword", "uvalue", "tvalue", "f", "q'x"])
    func `a prefix without a quote does not open a string`(_ input: String) {
        var scanner = PythonExternalScanner()
        #expect(scan(input, offering: ["string_start"], scanner: &scanner).name == nil)
        #expect(scanner.delimiters.isEmpty)
    }

    @Test(arguments: [("'", "'"), ("\"", "\""), ("'''", "'''"), ("\"\"\"", "\"\"\"")])
    func `single and triple quoted strings emit content before the end`(_ start: String, _ end: String) {
        var scanner = PythonExternalScanner()
        #expect(scan(start, offering: ["string_start"], scanner: &scanner).name == "string_start")
        let content = scan("text" + end, offering: ["_string_content", "string_end"], scanner: &scanner)
        #expect(content.name == "_string_content")
        #expect(content.lexer.tokenEnd == 4)
        #expect(scan(end, offering: ["_string_content", "string_end"], scanner: &scanner).name == "string_end")
        #expect(scanner.delimiters.isEmpty)
    }

    @Test
    func `format string braces interrupt content and doubled braces escape interpolation`() {
        var scanner = PythonExternalScanner()
        #expect(scan("f\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        let content = scan("a {b}", offering: ["_string_content", "escape_interpolation"], scanner: &scanner)
        #expect(content.name == "_string_content")
        #expect(content.lexer.tokenEnd == 2)
        #expect(scan("{b}", offering: ["_string_content", "escape_interpolation"], scanner: &scanner).name == nil)
        #expect(scan("{{", offering: ["escape_interpolation"], scanner: &scanner).name == "escape_interpolation")
        #expect(scan("}}", offering: ["escape_interpolation"], scanner: &scanner).name == "escape_interpolation")
        #expect(scan("}", offering: ["escape_interpolation"], scanner: &scanner).name == nil)
    }

    @Test
    func `raw and bytes strings handle backslashes according to their flags`() {
        var raw = PythonExternalScanner()
        #expect(scan("r\"", offering: ["string_start"], scanner: &raw).name == "string_start")
        #expect(scan("\\\"x\"", offering: ["_string_content", "string_end"], scanner: &raw).lexer.tokenEnd == 3)
        var bytes = PythonExternalScanner()
        #expect(scan("b\"", offering: ["string_start"], scanner: &bytes).name == "string_start")
        #expect(scan("x\\u0041\"", offering: ["_string_content"], scanner: &bytes).lexer.tokenEnd == 7)
        var plain = PythonExternalScanner()
        #expect(scan("\"", offering: ["string_start"], scanner: &plain).name == "string_start")
        #expect(scan("x\\n\"", offering: ["_string_content"], scanner: &plain).lexer.tokenEnd == 1)
    }

    @Test
    func `indentation stack handles tabs spaces blank lines comments and continued lines`() {
        var scanner = PythonExternalScanner()
        #expect(scan("\n\n# comment\n\titem", offering: ["_indent", "_newline"], scanner: &scanner).name == "_indent")
        #expect(scanner.indents == [0, 8])
        #expect(
            scan("\n        # same block\n        item", offering: ["_dedent", "_newline"], scanner: &scanner).name
                == "_newline")
        #expect(scanner.indents == [0, 8])
        #expect(scan("\\\n        item", offering: ["_indent", "_dedent", "_newline"], scanner: &scanner).name == nil)
        #expect(scan("\nitem", offering: ["_dedent"], scanner: &scanner).name == "_dedent")
        #expect(scanner.indents == [0])
    }

    @Test
    func `bracket signals suppress implicit dedent but do not emit closing brackets`() {
        var scanner = PythonExternalScanner()
        #expect(scan("\n    item", offering: ["_indent"], scanner: &scanner).name == "_indent")
        #expect(scan("\n]", offering: ["]"], scanner: &scanner).name == nil)
        #expect(scan("\n)", offering: [")"], scanner: &scanner).name == nil)
        #expect(scan("\n}", offering: ["}"], scanner: &scanner).name == nil)
        #expect(scanner.indents == [0, 4])
    }

    @Test
    func `comments and except are gates rather than scanner results`() {
        var scanner = PythonExternalScanner()
        #expect(scan("# comment", offering: ["comment"], scanner: &scanner).name == nil)
        #expect(scan("except:", offering: ["except"], scanner: &scanner).name == nil)
        #expect(scan("value # comment", offering: ["_newline", "comment"], scanner: &scanner).name == nil)
    }

    @Test
    func `unoffered tokens leave scanner state unchanged`() {
        var scanner = PythonExternalScanner()
        #expect(scan("\n    item", offering: [], scanner: &scanner).name == nil)
        #expect(scanner.indents == [0])
        #expect(scan("\"", offering: [], scanner: &scanner).name == nil)
        #expect(scanner.delimiters.isEmpty)
        #expect(scan("\n    item", offering: ["_indent"], scanner: &scanner).name == "_indent")
        #expect(scan("\nitem", offering: ["_newline"], scanner: &scanner).name == "_newline")
        #expect(scanner.indents == [0, 4])
        #expect(scan("\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        #expect(scan("\"", offering: ["_string_content"], scanner: &scanner).name == nil)
        #expect(scanner.delimiters.count == 1)
    }

    @Test
    func `all valid symbols enter error recovery without emitting a string token`() {
        var scanner = PythonExternalScanner()
        #expect(scan("\"", offering: PythonExternalScanner.externalNames, scanner: &scanner).name == "string_start")
        #expect(scan("{{", offering: PythonExternalScanner.externalNames, scanner: &scanner).name == nil)
        #expect(scanner.delimiters.count == 1)
        var fresh = PythonExternalScanner()
        #expect(scan("\n", offering: PythonExternalScanner.externalNames, scanner: &fresh).name == nil)
    }

    @Test
    func `deep indentation serialization stays within the parser state limit`() {
        var scanner = PythonExternalScanner()
        scanner.indents = (0 ... 600).map { UInt16($0) }
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == maximumSerializedScannerStateSize)
        var restored = PythonExternalScanner()
        restored.deserialize(state[...])
        #expect(restored.indents.count == 512)
        #expect(restored.indents.last == 511)
    }

    @Test
    func `serialized state round trips and empty state resets it`() {
        var scanner = PythonExternalScanner()
        #expect(scan("\n    item", offering: ["_indent"], scanner: &scanner).name == "_indent")
        #expect(scan("f\"\"\"", offering: ["string_start"], scanner: &scanner).name == "string_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(!state.isEmpty)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = PythonExternalScanner()
        restored.deserialize(state[...])
        #expect(restored.indents == scanner.indents)
        #expect(restored.delimiters == scanner.delimiters)
        #expect(restored.insideInterpolatedString == scanner.insideInterpolatedString)
        let padded = [UInt8.max] + state + [UInt8.max]
        restored.deserialize(padded[1 ..< padded.count - 1])
        #expect(restored.indents == scanner.indents)
        #expect(restored.delimiters == scanner.delimiters)
        restored.deserialize([])
        #expect(restored.indents == [0])
        #expect(restored.delimiters.isEmpty)
        #expect(!restored.insideInterpolatedString)
    }
}
