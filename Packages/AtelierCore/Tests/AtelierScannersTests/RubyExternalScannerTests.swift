import AtelierParser
import Testing

@testable import AtelierScanners

struct RubyTokenCase: Sendable {
    let name: String
    let input: String
    let rejectedInput: String
    let offered: [String]

    init(_ name: String, _ input: String, rejecting rejectedInput: String, offered: [String]? = nil) {
        self.name = name
        self.input = input
        self.rejectedInput = rejectedInput
        self.offered = offered ?? [name]
    }
}

private let directCases: [RubyTokenCase] = [
    .init("_line_break", "\nnext", rejecting: " next", offered: ["_line_break"]),
    .init("simple_symbol", ":name", rejecting: ":", offered: ["_symbol_start", "simple_symbol"]),
    .init("_string_start", "\"hello", rejecting: "hello"),
    .init("_symbol_start", ":\"name", rejecting: ":name"),
    .init("_subshell_start", "`date`", rejecting: "date", offered: ["_string_start", "_subshell_start"]),
    .init("_regex_start", "/ruby/", rejecting: "ruby", offered: ["_string_start", "_regex_start"]),
    .init(
        "_string_array_start", "%w[one two]", rejecting: "%j[one]", offered: ["_string_start", "_string_array_start"]),
    .init(
        "_symbol_array_start", "%i(one two)", rejecting: "%j(one)", offered: ["_string_start", "_symbol_array_start"]),
    .init("heredoc_beginning", "<<ID", rejecting: "<<", offered: ["_string_start", "heredoc_beginning"]),
    .init("_block_ampersand", "&block", rejecting: "&&block"),
    .init("_splat_star", " *args", rejecting: " *=value"),
    .init("_unary_minus", " -value", rejecting: "-="),
    .init("_unary_minus_num", " -2", rejecting: " -value"),
    .init("_binary_minus", "- value", rejecting: "-="),
    .init("_binary_star", "* value", rejecting: "*="),
    .init("_singleton_class_left_angle_left_langle", "<<self", rejecting: "<self"),
    .init("hash_key_symbol", "name:", rejecting: "name::"),
    .init("_identifier_suffix", "name!", rejecting: "name!="),
    .init("_constant_suffix", "Name!", rejecting: "Name!="),
    .init("_hash_splat_star_star", " **options", rejecting: " **=options"),
    .init("_binary_star_star", "** value", rejecting: "**=value"),
    .init("_element_reference_bracket", "[0]", rejecting: "(0)")
]

struct RubyExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, offering names: [String], scanner: inout RubyExternalScanner
    ) -> (name: String?, lexer: StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = RubyExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? RubyExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `external names match the pinned grammar and registry`() {
        #expect(
            RubyExternalScanner.externalNames == [
                "_line_break", "_no_line_break", "simple_symbol", "_string_start", "_symbol_start",
                "_subshell_start", "_regex_start", "_string_array_start", "_symbol_array_start",
                "_heredoc_body_start", "string_content", "heredoc_content", "_string_end",
                "heredoc_end", "heredoc_beginning", "/", "_block_ampersand", "_splat_star",
                "_unary_minus", "_unary_minus_num", "_binary_minus", "_binary_star",
                "_singleton_class_left_angle_left_langle", "hash_key_symbol", "_identifier_suffix",
                "_constant_suffix", "_hash_splat_star_star", "_binary_star_star",
                "_element_reference_bracket", "_short_interpolation"
            ])
        #expect(BundledScanners.byGrammarName["ruby"] != nil)
    }

    @Test(arguments: directCases)
    func `each direct token has a positive and negative input`(_ testCase: RubyTokenCase) {
        var scanner = RubyExternalScanner()
        let positive = scan(testCase.input, offering: testCase.offered, scanner: &scanner)
        #expect(positive.name == testCase.name)
        scanner = RubyExternalScanner()
        let negative = scan(testCase.rejectedInput, offering: testCase.offered, scanner: &scanner)
        #expect(negative.name != testCase.name)
    }

    @Test(arguments: directCases)
    func `an unoffered direct token is not produced`(_ testCase: RubyTokenCase) {
        var scanner = RubyExternalScanner()
        #expect(scan(testCase.input, offering: [], scanner: &scanner).name == nil)
    }

    @Test(arguments: ["\nnext", "\n..range", "\n\nnext", "\r\nnext"])
    func `a statement boundary emits a line break`(_ input: String) {
        var scanner = RubyExternalScanner()
        let result = scan(input, offering: ["_line_break"], scanner: &scanner)
        #expect(result.name == "_line_break")
        #expect(result.lexer.tokenEnd == (input.utf8.first == UInt8(ascii: "\r") ? 1 : 0))
    }

    @Test(arguments: ["\n.call", "\n&.call", "\n# comment", "\\\nnext"])
    func `a continuation does not emit a line break`(_ input: String) {
        var scanner = RubyExternalScanner()
        #expect(scan(input, offering: ["_line_break"], scanner: &scanner).name == nil)
    }

    @Test
    func `no line break and slash are parser gates rather than scanner results`() {
        var scanner = RubyExternalScanner()
        #expect(scan("next", offering: ["_no_line_break"], scanner: &scanner).name == nil)
        scanner = RubyExternalScanner()
        #expect(scan("/", offering: ["/"], scanner: &scanner).name == nil)
        scanner = RubyExternalScanner()
        #expect(scan("\nnext", offering: ["_line_break", "_no_line_break"], scanner: &scanner).name == nil)
    }

    @Test
    func `a result outside valid symbols is rejected without changing scanner state`() {
        var scanner = RubyExternalScanner()
        #expect(scan(":name", offering: ["_symbol_start"], scanner: &scanner).name == nil)
        #expect(scan("<<ID", offering: ["_string_start"], scanner: &scanner).name == nil)
        #expect(scanner.openHeredocs.isEmpty)
        #expect(scan(" -value", offering: ["_unary_minus_num"], scanner: &scanner).name == nil)
        #expect(scan("\"", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        #expect(scan("text\"", offering: ["_string_end"], scanner: &scanner).name == nil)
        #expect(scanner.literalStack.count == 1)
    }

    @Test(arguments: [
        ("\"", "a", "\""), ("'", "a", "'"), ("`", "a", "`"),
        ("%w[", "one", "]"), ("%i(", "one", ")"), ("%q{", "a{b}c", "}"),
        ("%Q<", "a<b>c", ">"), ("%r|", "a", "|im")
    ])
    func `literal content and end follow the opening delimiter`(_ opening: String, _ content: String, _ end: String) {
        var scanner = RubyExternalScanner()
        let openingResult = scan(opening, offering: RubyExternalScanner.externalNames, scanner: &scanner)
        #expect(openingResult.name != nil)
        let contentResult = scan(content + end, offering: ["string_content", "_string_end"], scanner: &scanner)
        #expect(contentResult.name == "string_content")
        #expect(contentResult.lexer.tokenEnd == content.utf8.count)
        let endResult = scan(end, offering: ["string_content", "_string_end"], scanner: &scanner)
        #expect(endResult.name == "_string_end")
        #expect(scanner.literalStack.isEmpty)
    }

    @Test
    func `literal content and end each reject the other's input`() {
        var scanner = RubyExternalScanner()
        #expect(scan("%q{", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        #expect(scan("}", offering: ["string_content", "_string_end"], scanner: &scanner).name == "_string_end")
        scanner = RubyExternalScanner()
        #expect(scan("%q{", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        #expect(scan("text", offering: ["string_content", "_string_end"], scanner: &scanner).name == nil)
    }

    @Test
    func `braced and short interpolation interrupt an interpolating string`() {
        var scanner = RubyExternalScanner()
        #expect(scan("\"", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        let prefix = scan("text#{value}", offering: ["string_content", "_string_end"], scanner: &scanner)
        #expect(prefix.name == "string_content")
        #expect(prefix.lexer.tokenEnd == 4)
        #expect(scan("#{value}", offering: ["string_content", "_string_end"], scanner: &scanner).name == nil)
        #expect(
            scan("#@ivar", offering: ["string_content", "_string_end", "_short_interpolation"], scanner: &scanner).name
                == "_short_interpolation")
        #expect(
            scan("#@1", offering: ["string_content", "_string_end", "_short_interpolation"], scanner: &scanner).name
                != "_short_interpolation")
        #expect(
            scan("#$name", offering: ["string_content", "_string_end", "_short_interpolation"], scanner: &scanner).name
                == "_short_interpolation")
    }

    @Test
    func `a single quoted string does not offer interpolation`() {
        var scanner = RubyExternalScanner()
        #expect(scan("'", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        #expect(
            scan("#@ivar'", offering: ["string_content", "_string_end", "_short_interpolation"], scanner: &scanner).name
                == "string_content")
    }

    @Test(arguments: ["<<ID", "<<-ID", "<<~ID", "<<'ID'", "<<\"ID\"", "<<`ID`"])
    func `heredoc beginning accepts each corpus delimiter form`(_ opening: String) {
        var scanner = RubyExternalScanner()
        #expect(
            scan(opening, offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        #expect(scanner.openHeredocs.first?.word == Array("ID".utf8))
    }

    @Test
    func `heredoc body starts after its opening line and ends at its identifier`() {
        var scanner = RubyExternalScanner()
        #expect(scan("\nbody\nID\n", offering: ["_heredoc_body_start"], scanner: &scanner).name == nil)
        #expect(
            scan("<<ID", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        #expect(
            scan("\nbody\nID\n", offering: ["_heredoc_body_start"], scanner: &scanner).name == "_heredoc_body_start")
        let content = scan("\nbody\nID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner)
        #expect(content.name == "heredoc_content")
        #expect(content.lexer.tokenEnd == "\nbody\n".utf8.count)
        #expect(scan("ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
        #expect(scanner.openHeredocs.isEmpty)
    }

    @Test
    func `heredoc content and end reject an unmatched identifier`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("<<ID", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        #expect(
            scan("OTHER\nID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name
                == "heredoc_content")
        #expect(scan("ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
    }

    @Test
    func `two heredocs opened on one line close in order`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("<<A", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name == "heredoc_beginning"
        )
        #expect(
            scan("<<B", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name == "heredoc_beginning"
        )
        #expect(scanner.openHeredocs.count == 2)
        #expect(scan("\n", offering: ["_heredoc_body_start"], scanner: &scanner).name == "_heredoc_body_start")
        #expect(scan("A\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
        #expect(scan("\n", offering: ["_heredoc_body_start"], scanner: &scanner).name == "_heredoc_body_start")
        #expect(scan("B\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
        #expect(scanner.openHeredocs.isEmpty)
    }

    @Test
    func `heredoc interpolation interrupts content`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("<<ID", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        #expect(
            scan("hello #{name}", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name
                == "heredoc_content")
        #expect(scan("#{name}", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == nil)
        #expect(
            scan("#@ivar", offering: ["heredoc_content", "heredoc_end", "_short_interpolation"], scanner: &scanner).name
                == "_short_interpolation")
    }

    @Test
    func `a single quoted heredoc keeps interpolation text in its body`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("<<'ID'", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        #expect(
            scan(
                "#{value}\nID\n", offering: ["heredoc_content", "heredoc_end", "_short_interpolation"],
                scanner: &scanner
            )
            .name == "heredoc_content")
        #expect(scan("ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
    }

    @Test
    func `Unicode letters and decimal digits use scalar character classes`() {
        var scanner = RubyExternalScanner()
        #expect(scan("é!", offering: ["_identifier_suffix"], scanner: &scanner).name == "_identifier_suffix")
        scanner = RubyExternalScanner()
        #expect(scan("Ä!", offering: ["_constant_suffix"], scanner: &scanner).name == "_constant_suffix")
        scanner = RubyExternalScanner()
        #expect(scan(" -٣", offering: ["_unary_minus_num"], scanner: &scanner).name == "_unary_minus_num")
    }

    @Test
    func `slash chooses a regex only where the C scanner allows it`() {
        var scanner = RubyExternalScanner()
        let names = ["_string_start", "_regex_start", "/"]
        #expect(scan("/value/", offering: names, scanner: &scanner).name == nil)
        scanner = RubyExternalScanner()
        #expect(scan(" /value/", offering: names, scanner: &scanner).name == "_regex_start")
        scanner = RubyExternalScanner()
        #expect(scan(" /=value", offering: names, scanner: &scanner).name == nil)
    }

    @Test
    func `spacing chooses unary and binary operators`() {
        let names = [
            "_unary_minus", "_unary_minus_num", "_binary_minus", "_splat_star", "_binary_star", "_hash_splat_star_star",
            "_binary_star_star"
        ]
        var scanner = RubyExternalScanner()
        #expect(scan(" -value", offering: names, scanner: &scanner).name == "_unary_minus")
        scanner = RubyExternalScanner()
        #expect(scan("-value", offering: names, scanner: &scanner).name == "_binary_minus")
        scanner = RubyExternalScanner()
        #expect(scan(" -2", offering: names, scanner: &scanner).name == "_unary_minus_num")
        scanner = RubyExternalScanner()
        #expect(scan("*value", offering: names, scanner: &scanner).name == "_binary_star")
        scanner = RubyExternalScanner()
        #expect(scan(" *value", offering: names, scanner: &scanner).name == "_splat_star")
        scanner = RubyExternalScanner()
        #expect(scan("**value", offering: names, scanner: &scanner).name == "_binary_star_star")
        scanner = RubyExternalScanner()
        #expect(scan(" **value", offering: names, scanner: &scanner).name == "_hash_splat_star_star")
    }

    @Test
    func `bang suffixes are external and question suffixes stay with the grammar`() {
        let names = ["_identifier_suffix", "_constant_suffix"]
        var scanner = RubyExternalScanner()
        #expect(scan("name!", offering: names, scanner: &scanner).name == "_identifier_suffix")
        scanner = RubyExternalScanner()
        #expect(scan("Name!", offering: names, scanner: &scanner).name == "_constant_suffix")
        scanner = RubyExternalScanner()
        #expect(scan("name?", offering: names, scanner: &scanner).name == nil)
        scanner = RubyExternalScanner()
        #expect(scan("Name?", offering: names, scanner: &scanner).name == nil)
    }

    @Test
    func `whitespace and expression validity choose element reference brackets`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("[0]", offering: ["_element_reference_bracket", "_string_start"], scanner: &scanner).name
                == "_element_reference_bracket")
        scanner = RubyExternalScanner()
        #expect(scan(" [0]", offering: ["_element_reference_bracket", "_string_start"], scanner: &scanner).name == nil)
        scanner = RubyExternalScanner()
        #expect(
            scan(" [0]", offering: ["_element_reference_bracket"], scanner: &scanner).name
                == "_element_reference_bracket")
    }

    @Test
    func `indented heredoc endings require an indented opener`() {
        var scanner = RubyExternalScanner()
        #expect(
            scan("<<ID", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        let unindented = scan("\n  ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner)
        #expect(unindented.name == "heredoc_content")
        #expect(unindented.lexer.tokenEnd == "\n  ID\n".utf8.count)
        scanner = RubyExternalScanner()
        #expect(
            scan("<<~ID", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        let indented = scan("\n  ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner)
        #expect(indented.name == "heredoc_content")
        #expect(indented.lexer.tokenEnd == "\n  ".utf8.count)
        #expect(scan("ID\n", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner).name == "heredoc_end")
    }

    @Test
    func `all valid symbols use the C scanner's recovery order`() {
        let names = RubyExternalScanner.externalNames
        var scanner = RubyExternalScanner()
        #expect(scan("<<ID", offering: names, scanner: &scanner).name == "_singleton_class_left_angle_left_langle")
        scanner = RubyExternalScanner()
        #expect(scan("-2", offering: names, scanner: &scanner).name == "_binary_minus")
        scanner = RubyExternalScanner()
        #expect(scan("**value", offering: names, scanner: &scanner).name == "_binary_star_star")
        scanner = RubyExternalScanner()
        #expect(scan("\"", offering: names, scanner: &scanner).name == "_string_start")
        scanner = RubyExternalScanner()
        #expect(scan("/value/", offering: names, scanner: &scanner).name == nil)
    }

    @Test
    func `serialization restores open literals and ordered heredocs`() {
        var scanner = RubyExternalScanner()
        #expect(scan("%Q<", offering: ["_string_start"], scanner: &scanner).name == "_string_start")
        #expect(
            scan("<<A", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name == "heredoc_beginning"
        )
        #expect(
            scan("<<-B", offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                == "heredoc_beginning")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(!state.isEmpty)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = RubyExternalScanner()
        restored.deserialize(state[...])
        var repeated: [UInt8] = []
        restored.serialize(into: &repeated)
        #expect(repeated == state)
        #expect(scan("nested<part>", offering: ["string_content", "_string_end"], scanner: &restored).name == nil)
        #expect(scan(">", offering: ["string_content", "_string_end"], scanner: &restored).name == "_string_end")
        restored.deserialize([])
        #expect(restored.literalStack.isEmpty)
        #expect(restored.openHeredocs.isEmpty)
    }

    @Test
    func `an opening that cannot be serialized is rejected without losing earlier heredocs`() {
        var scanner = RubyExternalScanner()
        let word = String(repeating: "A", count: 250)
        for _ in 0 ..< 4 {
            #expect(
                scan("<<" + word, offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name
                    == "heredoc_beginning")
        }
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == 1_018)
        #expect(scan("<<" + word, offering: ["_string_start", "heredoc_beginning"], scanner: &scanner).name == nil)
        #expect(scanner.openHeredocs.count == 4)
        var afterRejection: [UInt8] = []
        scanner.serialize(into: &afterRejection)
        #expect(afterRejection == state)
        let longWord = String(repeating: "B", count: 256)
        var fresh = RubyExternalScanner()
        #expect(scan("<<" + longWord, offering: ["_string_start", "heredoc_beginning"], scanner: &fresh).name == nil)
        #expect(fresh.openHeredocs.isEmpty)
        scanner.deserialize([1, 3][...])
        #expect(scanner.literalStack.isEmpty)
        #expect(scanner.openHeredocs.isEmpty)
    }

    @Test(arguments: [
        [1, 30, 0, 0, 1, 0, 0],
        [1, 3, 34, 34, 0, 1, 0],
        [0, 1, 0, 1, 0, 0]
    ])
    func `malformed serialized structures reset rather than creating invalid scanner state`(_ bytes: [UInt8]) {
        var scanner = RubyExternalScanner()
        scanner.deserialize(bytes[...])
        #expect(scanner.literalStack.isEmpty)
        #expect(scanner.openHeredocs.isEmpty)
    }
}
