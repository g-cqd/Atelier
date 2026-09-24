import AtelierParser
import Testing

@testable import AtelierScanners

struct BashTokenCase: Sendable {
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

// Inputs are drawn from the pinned grammar's commands, literals, and statements corpus.
private let directCases: [BashTokenCase] = [
    .init("file_descriptor", "2>file", rejecting: "2x>file"),
    .init("_empty_value", " ", rejecting: "x"),
    .init("_concat", "tail", rejecting: " "),
    .init("variable_name", "name=value", rejecting: "name "),
    .init("test_operator", "-eq ", rejecting: "-eq"),
    .init("regex", "^[0-9] ]", rejecting: "\"abc\""),
    .init("_regex_no_slash", "foo/bar", rejecting: "/foo"),
    .init("_regex_no_space", "[a-z] ", rejecting: "abc "),
    .init("_expansion_word", "word${value}", rejecting: "${value}"),
    .init("extglob_pattern", "+(foo|bar) ", rejecting: "word "),
    .init("_bare_dollar", "$ ", rejecting: "$name"),
    .init("_brace_start", "{1..3}", rejecting: "{1.3}"),
    .init("_immediate_double_hash", "##name", rejecting: "##}"),
    .init("_external_expansion_sym_hash", "#}", rejecting: "#x"),
    .init(
        "_external_expansion_sym_bang", "!}", rejecting: "!x",
        offered: ["_external_expansion_sym_hash", "_external_expansion_sym_bang"]),
    .init(
        "_external_expansion_sym_equal", "=}", rejecting: "=x",
        offered: ["_external_expansion_sym_hash", "_external_expansion_sym_equal"]),
    .init("<<", "<<EOF", rejecting: "<EOF"),
    .init("<<-", "<<-EOF", rejecting: "<<=EOF", offered: ["<<", "<<-"])
]

struct BashExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, offering names: [String], scanner: inout BashExternalScanner
    ) -> (name: String?, lexer: StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = BashExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? BashExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `external names match the pinned Bash grammar and registry`() {
        #expect(
            BashExternalScanner.externalNames == [
                "heredoc_start", "simple_heredoc_body", "_heredoc_body_beginning", "heredoc_content",
                "heredoc_end", "file_descriptor", "_empty_value", "_concat", "variable_name", "test_operator",
                "regex", "_regex_no_slash", "_regex_no_space", "_expansion_word", "extglob_pattern",
                "_bare_dollar", "_brace_start", "_immediate_double_hash", "_external_expansion_sym_hash",
                "_external_expansion_sym_bang", "_external_expansion_sym_equal", "}", "]", "<<", "<<-",
                "\n", "(", "esac", "__error_recovery"
            ])
        #expect(BundledScanners.byGrammarName["bash"] != nil)
    }

    @Test
    func `heredoc arrows and delimiters retain their state`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<EOF", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan("EOF", offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count > 4)
    }

    @Test(arguments: directCases)
    func `each direct token accepts corpus input and rejects a boundary input`(_ testCase: BashTokenCase) {
        var scanner = BashExternalScanner()
        #expect(scan(testCase.input, offering: testCase.offered, scanner: &scanner).name == testCase.name)
        scanner = BashExternalScanner()
        #expect(scan(testCase.rejectedInput, offering: testCase.offered, scanner: &scanner).name != testCase.name)
    }

    @Test(arguments: directCases)
    func `each direct token obeys its valid symbols gate`(_ testCase: BashTokenCase) {
        var scanner = BashExternalScanner()
        #expect(scan(testCase.input, offering: [], scanner: &scanner).name == nil)
    }

    @Test(arguments: [
        ("EOF", "hello\nEOF", "simple_heredoc_body"),
        ("'EOF'", "literal $name\nEOF", "simple_heredoc_body"),
        ("\"EOF\"", "literal $name\nEOF", "simple_heredoc_body"),
        ("EOF", "hello $name\nEOF", "_heredoc_body_beginning")
    ])
    func `heredoc bodies distinguish literal and expanding delimiters`(
        _ delimiter: String, _ body: String, _ expected: String
    ) {
        var scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan(delimiter, offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        let result = scan(body, offering: ["simple_heredoc_body", "_heredoc_body_beginning"], scanner: &scanner)
        #expect(result.name == expected)
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &scanner).name == "heredoc_end")
        #expect(scan("other", offering: ["heredoc_end"], scanner: &scanner).name == nil)
    }

    @Test
    func `expanding heredoc emits content before a substitution`() {
        var scanner = BashExternalScanner()
        #expect(scan("text$name", offering: ["heredoc_content"], scanner: &scanner).name == nil)
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan("", offering: ["heredoc_start"], scanner: &scanner).name == nil)
        #expect(scan("EOF", offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        #expect(scan("WRONG", offering: ["heredoc_end"], scanner: &scanner).name == nil)
        #expect(
            scan("$name\nEOF", offering: ["_heredoc_body_beginning", "simple_heredoc_body"], scanner: &scanner)
                .name == "_heredoc_body_beginning")
        #expect(scan("$name", offering: ["simple_heredoc_body"], scanner: &scanner).name == nil)
        let content = scan("text$name\nEOF", offering: ["heredoc_content", "heredoc_end"], scanner: &scanner)
        #expect(content.name == "heredoc_content")
        #expect(content.lexer.tokenEnd == 4)
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &scanner).name == "heredoc_end")
    }

    @Test
    func `raw heredoc body rejects the expansion beginning token`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan("'EOF'", offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        #expect(scan("literal $name\nEOF", offering: ["_heredoc_body_beginning"], scanner: &scanner).name == nil)
        #expect(
            scan(
                "literal $name\nEOF", offering: ["simple_heredoc_body", "_heredoc_body_beginning"],
                scanner: &scanner
            )
            .name == "simple_heredoc_body")
    }

    @Test
    func `two heredocs on one line retain separate delimiters`() {
        var scanner = BashExternalScanner()
        let source = "cat <<A <<B\nb\nB\na\nA\n"
        #expect(scan(source, at: 4, offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan(source, at: 6, offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        #expect(scan(source, at: 8, offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan(source, at: 10, offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        #expect(
            scan(source, at: 12, offering: ["simple_heredoc_body", "_heredoc_body_beginning"], scanner: &scanner)
                .name == "simple_heredoc_body")
        #expect(scan(source, at: 14, offering: ["heredoc_end"], scanner: &scanner).name == "heredoc_end")
        #expect(
            scan(source, at: 16, offering: ["simple_heredoc_body", "_heredoc_body_beginning"], scanner: &scanner)
                .name == "simple_heredoc_body")
        #expect(scan(source, at: 18, offering: ["heredoc_end"], scanner: &scanner).name == "heredoc_end")
    }

    @Test
    func `unoffered heredoc token leaves state unchanged`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<-", offering: ["<<"], scanner: &scanner).name == nil)
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0, 0, 0])
        #expect(scan("!}", offering: ["_external_expansion_sym_hash"], scanner: &scanner).name == nil)
        var after: [UInt8] = []
        scanner.serialize(into: &after)
        #expect(after == state)
    }

    @Test
    func `all valid symbols trigger error recovery gates`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<EOF", offering: BashExternalScanner.externalNames, scanner: &scanner).name == nil)
        #expect(scan("##name", offering: BashExternalScanner.externalNames, scanner: &scanner).name == nil)
        #expect(scan(" ", offering: BashExternalScanner.externalNames, scanner: &scanner).name == "_empty_value")
    }

    @Test
    func `serialization restores a pending heredoc and empty state resets it`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan("EOF", offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count <= maximumSerializedScannerStateSize)
        var restored = BashExternalScanner()
        restored.deserialize(state[...])
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &restored).name == "heredoc_end")
        restored.deserialize(([0xFF] + state).dropFirst())
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &restored).name == "heredoc_end")
        restored.deserialize([])
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &restored).name == nil)
    }

    @Test
    func `malformed serialized state resets without partial heredocs`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(scan("EOF", offering: ["heredoc_start"], scanner: &scanner).name == "heredoc_start")
        scanner.deserialize([0, 0, 0, 1, 0, 0, 0, 4][...])
        #expect(scan("EOF", offering: ["heredoc_end"], scanner: &scanner).name == nil)
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0, 0, 0])
    }

    @Test
    func `character classes use Unicode scalar properties`() {
        var scanner = BashExternalScanner()
        #expect(scan("ä=value", offering: ["variable_name"], scanner: &scanner).name == "variable_name")
        #expect(scan("٢>file", offering: ["file_descriptor"], scanner: &scanner).name == "file_descriptor")
        #expect(scan("-eq\u{2003}", offering: ["test_operator"], scanner: &scanner).name == "test_operator")
        #expect(scan("-²|bar", offering: ["extglob_pattern"], scanner: &scanner).name == "extglob_pattern")
    }

    @Test
    func `serialized state stays within tree sitter's limit`() {
        var scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(
            scan(String(repeating: "E", count: 1011), offering: ["heredoc_start"], scanner: &scanner)
                .name == "heredoc_start")
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state.count == maximumSerializedScannerStateSize - 1)

        scanner = BashExternalScanner()
        #expect(scan("<<", offering: ["<<"], scanner: &scanner).name == "<<")
        #expect(
            scan(String(repeating: "E", count: 1012), offering: ["heredoc_start"], scanner: &scanner)
                .name == "heredoc_start")
        state.removeAll()
        scanner.serialize(into: &state)
        #expect(state.isEmpty)
    }

    @Test
    func `closing punctuation gates concat and variable names`() {
        var scanner = BashExternalScanner()
        #expect(scan("}", offering: ["_concat", "}"], scanner: &scanner).name == nil)
        #expect(scan("}", offering: ["_concat"], scanner: &scanner).name == "_concat")
        #expect(scan("]", offering: ["_concat", "]"], scanner: &scanner).name == nil)
        #expect(scan("]", offering: ["_concat"], scanner: &scanner).name == "_concat")
        #expect(scan("name:rest", offering: ["variable_name"], scanner: &scanner).name == "variable_name")
        #expect(scan("name:rest", offering: ["variable_name", "("], scanner: &scanner).name == nil)
        #expect(scan("name-", offering: ["variable_name", "}"], scanner: &scanner).name == "variable_name")
    }

    @Test
    func `newline gate controls multiline test operators`() {
        var scanner = BashExternalScanner()
        #expect(scan("\n-eq ", offering: ["test_operator"], scanner: &scanner).name == "test_operator")
        #expect(scan("\n-eq ", offering: ["test_operator", "\n"], scanner: &scanner).name == nil)
    }

    @Test
    func `esac and punctuation are parser gates rather than scanner results`() {
        var scanner = BashExternalScanner()
        for (input, name) in [("esac", "esac"), ("}", "}"), ("]", "]"), ("(", "("), ("\n", "\n")] {
            #expect(scan(input, offering: [name], scanner: &scanner).name == nil)
        }
        let esac = scan("esac ", offering: ["extglob_pattern"], scanner: &scanner)
        #expect(esac.name == nil)
        #expect(esac.lexer.tokenEnd == 0)
    }
}
