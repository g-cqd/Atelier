import AtelierParser
import Testing

@testable import AtelierScanners

struct TokenCase: Sendable {
    let name: String
    let input: String
    let rejectedInput: String
}

private let tokenCases: [TokenCase] = [
    .init(name: "multiline_comment", input: "/* Hello world */", rejectedInput: "/* unfinished"),
    .init(name: "raw_str_part", input: "#\"Hello \\#(", rejectedInput: "#\"unfinished"),
    .init(name: "raw_str_end_part", input: "##\"Hello\"##", rejectedInput: "##\"Hello\"#"),
    .init(name: "_arrow_operator_custom", input: "-> ", rejectedInput: "- >"),
    .init(name: "_dot_custom", input: ".name", rejectedInput: "..name"),
    .init(name: "_conjunction_operator_custom", input: "&& ", rejectedInput: "& &"),
    .init(name: "_disjunction_operator_custom", input: "|| ", rejectedInput: "| |"),
    .init(name: "_nil_coalescing_operator_custom", input: "?? ", rejectedInput: "? ?"),
    .init(name: "_eq_custom", input: "= ", rejectedInput: "==="),
    .init(name: "_eq_eq_custom", input: "== ", rejectedInput: "= ="),
    .init(name: "_plus_then_ws", input: "+ ", rejectedInput: "+x"),
    .init(name: "_minus_then_ws", input: "- ", rejectedInput: "-x"),
    .init(name: "_bang_custom", input: "!x", rejectedInput: "!!x"),
    .init(name: "_throws_keyword", input: "throws ", rejectedInput: "throwsValue"),
    .init(name: "_rethrows_keyword", input: "rethrows ", rejectedInput: "rethrowsValue"),
    .init(name: "default_keyword", input: "default ", rejectedInput: "defaultValue"),
    .init(name: "where_keyword", input: "where ", rejectedInput: "wherever"),
    .init(name: "else", input: "else ", rejectedInput: "elsewhere"),
    .init(name: "catch_keyword", input: "catch ", rejectedInput: "catcher"),
    .init(name: "_as_custom", input: "as ", rejectedInput: "ask"),
    .init(name: "_as_quest_custom", input: "as? ", rejectedInput: "as??"),
    .init(name: "_as_bang_custom", input: "as! ", rejectedInput: "as!!"),
    .init(name: "_async_keyword_custom", input: "async ", rejectedInput: "asynchronous"),
    .init(name: "_custom_operator", input: "/!5", rejectedInput: "/* comment */"),
    .init(name: "_hash_symbol_custom", input: "#unknown", rejectedInput: "unknown"),
    .init(name: "_directive_if", input: "#if DEBUG", rejectedInput: "#unknown"),
    .init(name: "_directive_elseif", input: "#elseif DEBUG", rejectedInput: "#unknown"),
    .init(name: "_directive_else", input: "#else", rejectedInput: "#unknown"),
    .init(name: "_directive_endif", input: "#endif", rejectedInput: "#unknown")
]

struct SwiftExternalScannerTests {
    private func scan(_ input: String, allowing names: [String], scanner: inout SwiftExternalScanner) -> (
        name: String?, lexer: StringScannerLexer
    ) {
        var lexer = StringScannerLexer(input)
        let valid = SwiftExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? SwiftExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `external names match the pinned grammar order`() {
        #expect(
            SwiftExternalScanner.externalNames == [
                "multiline_comment", "raw_str_part", "raw_str_continuing_indicator", "raw_str_end_part",
                "_implicit_semi", "_explicit_semi", "_arrow_operator_custom", "_dot_custom",
                "_conjunction_operator_custom", "_disjunction_operator_custom", "_nil_coalescing_operator_custom",
                "_eq_custom", "_eq_eq_custom", "_plus_then_ws", "_minus_then_ws", "_bang_custom",
                "_throws_keyword", "_rethrows_keyword", "default_keyword", "where_keyword", "else",
                "catch_keyword", "_as_custom", "_as_quest_custom", "_as_bang_custom", "_async_keyword_custom",
                "_custom_operator", "_hash_symbol_custom", "_directive_if", "_directive_elseif", "_directive_else",
                "_directive_endif", "_fake_try_bang"
            ])
        #expect(BundledScanners.byGrammarName["swift"] != nil)
    }

    @Test(arguments: tokenCases)
    func `each concrete token has a positive and negative input`(_ testCase: TokenCase) {
        var scanner = SwiftExternalScanner()
        let requiresRawEntry =
            testCase.name == "raw_str_end_part" || testCase.name == "_hash_symbol_custom"
            || testCase.name.hasPrefix("_directive_")
        let allowed = requiresRawEntry ? [testCase.name, "raw_str_part"] : [testCase.name]
        let positive = scan(testCase.input, allowing: allowed, scanner: &scanner)
        #expect(positive.name == testCase.name)
        scanner = SwiftExternalScanner()
        let negative = scan(testCase.rejectedInput, allowing: allowed, scanner: &scanner)
        #expect(negative.name != testCase.name)
    }

    @Test(arguments: ["\nnext", "\rnext", "\n  next"])
    func `line breaks produce implicit semicolons`(_ input: String) {
        var scanner = SwiftExternalScanner()
        let result = scan(input, allowing: ["_implicit_semi", "_explicit_semi"], scanner: &scanner)
        #expect(result.name == "_implicit_semi")
        #expect(result.lexer.tokenEnd == result.lexer.tokenStart)
    }

    @Test(arguments: ["\n= 0", "\nelse", "\n? value", "\n: value", "\n{ value"])
    func `continuation punctuation suppresses a semicolon`(_ input: String) {
        var scanner = SwiftExternalScanner()
        let result = scan(
            input, allowing: ["_implicit_semi", "_explicit_semi", "_eq_custom", "else"], scanner: &scanner)
        #expect(result.name != "_implicit_semi")
    }

    @Test
    func `explicit semicolon requires both semicolon symbols`() {
        var scanner = SwiftExternalScanner()
        #expect(
            scan("; next", allowing: ["_implicit_semi", "_explicit_semi"], scanner: &scanner).name == "_explicit_semi")
        scanner = SwiftExternalScanner()
        #expect(scan("; next", allowing: ["_explicit_semi"], scanner: &scanner).name == nil)
    }

    @Test
    func `a line comment after a newline does not create a semicolon`() {
        var scanner = SwiftExternalScanner()
        #expect(scan("\n// note\nnext", allowing: ["_implicit_semi", "_explicit_semi"], scanner: &scanner).name == nil)
    }

    @Test
    func `raw delimiters and directives require their result symbol to be offered`() {
        var scanner = SwiftExternalScanner()
        #expect(scan("#\"value\"#", allowing: ["raw_str_part"], scanner: &scanner).name == nil)
        scanner = SwiftExternalScanner()
        #expect(scan("#if DEBUG", allowing: ["raw_str_part"], scanner: &scanner).name == nil)
    }

    @Test
    func `invalid UTF8 does not produce a token`() {
        var scanner = SwiftExternalScanner()
        var lexer = StringScannerLexer(utf8: [0xFF])
        #expect(
            !scanner.scan(
                &lexer, validSymbols: [Bool](repeating: true, count: SwiftExternalScanner.externalNames.count)))
    }

    @Test
    func `Unicode operator scalars scan without byte splitting`() {
        var scanner = SwiftExternalScanner()
        let result = scan("→value", allowing: ["_custom_operator"], scanner: &scanner)
        #expect(result.name == "_custom_operator")
        #expect(result.lexer.tokenEnd == "→".utf8.count)
    }

    @Test
    func `nested block comments end at the outer closing delimiter`() {
        var scanner = SwiftExternalScanner()
        let input = "/* outer /* inner */ tail */ next"
        let result = scan(input, allowing: ["multiline_comment"], scanner: &scanner)
        #expect(result.name == "multiline_comment")
        #expect(result.lexer.tokenEnd == "/* outer /* inner */ tail */".utf8.count)
    }

    @Test
    func `raw multiline strings require matching closing hashes`() {
        var scanner = SwiftExternalScanner()
        let input = "##\"\"\"line\n\"# still inside\n\"\"\"##"
        let result = scan(input, allowing: ["raw_str_part", "raw_str_end_part"], scanner: &scanner)
        #expect(result.name == "raw_str_end_part")
        #expect(result.lexer.tokenEnd == input.utf8.count)
    }

    @Test
    func `raw interpolation preserves its hash count across serialization`() {
        var scanner = SwiftExternalScanner()
        let first = scan("##\"value \\##(x)", allowing: ["raw_str_part"], scanner: &scanner)
        #expect(first.name == "raw_str_part")
        #expect(first.lexer.tokenEnd == "##\"value ".utf8.count)
        var bytes: [UInt8] = []
        scanner.serialize(into: &bytes)
        #expect(bytes == [0, 0, 0, 2])
        var restored = SwiftExternalScanner()
        restored.deserialize(bytes[...])
        let resumed = scan(
            " after\"##", allowing: ["raw_str_part", "raw_str_continuing_indicator", "raw_str_end_part"],
            scanner: &restored)
        #expect(resumed.name == "raw_str_end_part")
        restored.deserialize([])
        let reset = scan(
            " after\"##", allowing: ["raw_str_part", "raw_str_continuing_indicator", "raw_str_end_part"],
            scanner: &restored)
        #expect(reset.name == nil)
    }

    @Test
    func `synthetic markers and fake try bang are never emitted`() {
        var scanner = SwiftExternalScanner()
        #expect(
            scan("anything", allowing: ["raw_str_continuing_indicator", "_fake_try_bang"], scanner: &scanner).name
                == nil)
    }

    @Test(arguments: tokenCases)
    func `unoffered concrete tokens are not emitted`(_ testCase: TokenCase) {
        var scanner = SwiftExternalScanner()
        let result = scan(testCase.input, allowing: [], scanner: &scanner)
        #expect(result.name == nil)
    }

    @Test
    func `all valid symbols follow C scanner recovery order`() {
        let names = SwiftExternalScanner.externalNames
        var scanner = SwiftExternalScanner()
        #expect(scan("\n= 0", allowing: names, scanner: &scanner).name == "_eq_custom")
        scanner = SwiftExternalScanner()
        #expect(scan("/* nested /* child */ end */", allowing: names, scanner: &scanner).name == "multiline_comment")
        scanner = SwiftExternalScanner()
        #expect(scan("#if DEBUG", allowing: names, scanner: &scanner).name == "_directive_if")
        scanner = SwiftExternalScanner()
        #expect(scan("!x", allowing: names, scanner: &scanner).name == nil)
    }
}
