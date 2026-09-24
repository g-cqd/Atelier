import AtelierParser
import Testing

@testable import AtelierScanners

struct MarkdownCase: Sendable {
    let token: String
    let input: String
    let rejected: String
    let extras: [String]

    init(_ token: String, _ input: String, _ rejected: String, extras: [String] = []) {
        self.token = token
        self.input = input
        self.rejected = rejected
        self.extras = extras
    }
}

// Examples are drawn from the pinned upstream spec and extension corpus cases.
private let markdownCases: [MarkdownCase] = [
    .init("_line_ending", "\nnext", "plain text"),
    .init("_soft_line_ending", "\nnext", "plain text"),
    .init("_pipe_table_line_ending", "\nnext", "plain text"),
    .init("_block_quote_start", "> foo\n", "plain text"),
    .init("_indented_chunk_start", "    code\n", "   code\n"),
    .init("atx_h1_marker", "# foo\n", "####### Heading\n"),
    .init("atx_h2_marker", "## foo\n", "####### Heading\n", extras: ["atx_h1_marker"]),
    .init("atx_h3_marker", "### foo\n", "####### Heading\n", extras: ["atx_h1_marker"]),
    .init("atx_h4_marker", "#### foo\n", "####### Heading\n", extras: ["atx_h1_marker"]),
    .init("atx_h5_marker", "##### foo\n", "####### Heading\n", extras: ["atx_h1_marker"]),
    .init("atx_h6_marker", "###### foo\n", "####### Heading\n", extras: ["atx_h1_marker"]),
    .init("setext_h1_underline", "===\n", "== title\n"),
    .init("setext_h2_underline", "---\n", "-- title\n"),
    .init("_thematic_break", "* * *\n", "* * text\n"),
    .init("_list_marker_minus", "- foo\n", "-item\n"),
    .init("_list_marker_plus", "+ baz\n", "+item\n"),
    .init("_list_marker_star", "* List item\n", "*item\n"),
    .init("_list_marker_parenthesis", "10) foo\n", "1)item\n", extras: ["_list_marker_parenthesis_dont_interrupt"]),
    .init("_list_marker_dot", "1. a\n", "1.item\n"),
    .init("_list_marker_minus_dont_interrupt", "-\n", "-item\n"),
    .init("_list_marker_plus_dont_interrupt", "+\n", "+item\n"),
    .init("_list_marker_star_dont_interrupt", "*\n", "*item\n"),
    .init("_fenced_code_block_start_backtick", "```{R}\n", "```bad`\n"),
    .init("_fenced_code_block_start_tilde", "~~~swift\n", "~~swift\n"),
    .init("_blank_line_start", "\n", "plain text"),
    .init("_fenced_code_block_end_backtick", "```\n", "`` x\n"),
    .init("_fenced_code_block_end_tilde", "~~~\n", "~~ x\n"),
    .init("_html_block_1_start", "<script>\n", "<scripture>\n"),
    .init("_html_block_1_end", "</script>\n", "</scripture>\n"),
    .init("_html_block_2_start", "<!-- comment -->\n", "<!- comment -->\n"),
    .init("_html_block_3_start", "<?xml?>\n", "<xml?>\n"),
    .init("_html_block_4_start", "<!DOCTYPE html>\n", "<!doctype html>\n"),
    .init("_html_block_5_start", "<![CDATA[data]]>\n", "<![CDATAdata]]>\n"),
    .init("_html_block_6_start", "<div>\n", "<divider>\n"),
    .init("_html_block_7_start", "<custom a=\"b\">\n", "<custom a=>\n"),
    .init("_eof", "", "plain text"),
    .init("minus_metadata", "---\nkey: value\n---\n", "---\nkey: value\n--\n"),
    .init("plus_metadata", "+++\nkey: value\n+++\n", "+++\nkey: value\n++\n"),
    .init("_pipe_table_start", "| foo | bar |\n| --- | --- |\n| baz | bim |\n", "| a | b |\n| --- |\n")
]

struct MarkdownExternalScannerTests {
    private func scan(
        _ input: String, at offset: Int = 0, allowing names: [String], scanner: inout MarkdownExternalScanner
    ) -> (name: String?, lexer: StringScannerLexer) {
        var lexer = StringScannerLexer(input, at: offset)
        let valid = MarkdownExternalScanner.externalNames.map { names.contains($0) }
        let found = scanner.scan(&lexer, validSymbols: valid)
        return (found ? MarkdownExternalScanner.externalNames[lexer.resultSymbol] : nil, lexer)
    }

    @Test
    func `external names and registration match the pinned grammar`() {
        #expect(
            MarkdownExternalScanner.externalNames == [
                "_line_ending", "_soft_line_ending", "_block_close", "block_continuation", "_block_quote_start",
                "_indented_chunk_start", "atx_h1_marker", "atx_h2_marker", "atx_h3_marker", "atx_h4_marker",
                "atx_h5_marker", "atx_h6_marker", "setext_h1_underline", "setext_h2_underline", "_thematic_break",
                "_list_marker_minus", "_list_marker_plus", "_list_marker_star", "_list_marker_parenthesis",
                "_list_marker_dot",
                "_list_marker_minus_dont_interrupt", "_list_marker_plus_dont_interrupt",
                "_list_marker_star_dont_interrupt",
                "_list_marker_parenthesis_dont_interrupt", "_list_marker_dot_dont_interrupt",
                "_fenced_code_block_start_backtick", "_fenced_code_block_start_tilde", "_blank_line_start",
                "_fenced_code_block_end_backtick", "_fenced_code_block_end_tilde", "_html_block_1_start",
                "_html_block_1_end",
                "_html_block_2_start", "_html_block_3_start", "_html_block_4_start", "_html_block_5_start",
                "_html_block_6_start", "_html_block_7_start", "_close_block", "_no_indented_chunk", "_error",
                "_trigger_error", "_eof", "minus_metadata", "plus_metadata", "_pipe_table_start",
                "_pipe_table_line_ending"
            ])
        #expect(BundledScanners.byGrammarName["markdown"] != nil)
    }

    @Test(arguments: markdownCases)
    func `each direct token accepts its corpus case and rejects malformed input`(_ testCase: MarkdownCase) {
        var scanner = MarkdownExternalScanner()
        let allowed = [testCase.token] + testCase.extras
        let positive = scan(testCase.input, allowing: allowed, scanner: &scanner)
        #expect(positive.name == testCase.token)
        scanner = MarkdownExternalScanner()
        let negative = scan(testCase.rejected, allowing: allowed, scanner: &scanner)
        #expect(negative.name != testCase.token)
    }

    @Test
    func `block quote continuation and close follow the open block stack`() {
        var scanner = MarkdownExternalScanner()
        let text = "> quote\n> more\n"
        #expect(scan(text, allowing: ["_block_quote_start"], scanner: &scanner).name == "_block_quote_start")
        #expect(scan(text, at: 7, allowing: ["_line_ending"], scanner: &scanner).name == "_line_ending")
        #expect(scan(text, at: 8, allowing: ["block_continuation"], scanner: &scanner).name == "block_continuation")
        let close = scan("", allowing: ["_block_close"], scanner: &scanner)
        #expect(close.name == "_block_close")
        #expect(scan("", allowing: ["_block_close"], scanner: &scanner).name == nil)
        #expect(scan("plain", allowing: ["block_continuation"], scanner: &scanner).name == nil)
    }

    @Test
    func `list indentation continues only with enough spaces`() {
        var scanner = MarkdownExternalScanner()
        #expect(scan("- item\n", allowing: ["_list_marker_minus"], scanner: &scanner).name == "_list_marker_minus")
        #expect(scan("- item\n", at: 6, allowing: ["_line_ending"], scanner: &scanner).name == "_line_ending")
        #expect(scan("  continued\n", allowing: ["block_continuation"], scanner: &scanner).name == "block_continuation")
        scanner = MarkdownExternalScanner()
        #expect(scan("- item\n", allowing: ["_list_marker_minus"], scanner: &scanner).name == "_list_marker_minus")
        #expect(scan("- item\n", at: 6, allowing: ["_line_ending"], scanner: &scanner).name == "_line_ending")
        #expect(scan("next\n", allowing: ["_block_close"], scanner: &scanner).name == "_block_close")
    }

    @Test
    func `fence close uses the opening delimiter length`() {
        var scanner = MarkdownExternalScanner()
        #expect(
            scan("````\n", allowing: ["_fenced_code_block_start_backtick"], scanner: &scanner).name
                == "_fenced_code_block_start_backtick")
        #expect(scan("```\n", allowing: ["_fenced_code_block_end_backtick"], scanner: &scanner).name == nil)
        #expect(
            scan("````\n", allowing: ["_fenced_code_block_end_backtick"], scanner: &scanner).name
                == "_fenced_code_block_end_backtick")
    }

    @Test
    func `soft line ending allows a lazy continuation line`() {
        var scanner = MarkdownExternalScanner()
        let result = scan("\ncontinued\n", allowing: ["_soft_line_ending", "_line_ending"], scanner: &scanner)
        #expect(result.name == "_soft_line_ending")
        #expect(result.lexer.tokenEnd == 1)
    }

    @Test
    func `all valid symbols produce the recovery error token`() {
        var scanner = MarkdownExternalScanner()
        let valid = [Bool](repeating: true, count: MarkdownExternalScanner.externalNames.count)
        var lexer = StringScannerLexer("# heading\n")
        #expect(scanner.scan(&lexer, validSymbols: valid))
        #expect(MarkdownExternalScanner.externalNames[lexer.resultSymbol] == "_error")
        #expect(lexer.tokenEnd == 0)
    }

    @Test
    func `close block and error tokens require their control symbols`() {
        var scanner = MarkdownExternalScanner()
        #expect(scan("text", allowing: ["_close_block"], scanner: &scanner).name == "_close_block")
        scanner = MarkdownExternalScanner()
        #expect(scan("text", allowing: [], scanner: &scanner).name == nil)
        #expect(scan("text", allowing: ["_trigger_error", "_error"], scanner: &scanner).name == "_error")
        scanner = MarkdownExternalScanner()
        #expect(scan("text", allowing: ["_error"], scanner: &scanner).name == nil)
    }

    @Test
    func `reference definition ends at its line break`() {
        var scanner = MarkdownExternalScanner()
        let definition = "[foo]: /url \"title\"\n"
        let result = scan(definition, at: definition.utf8.count - 1, allowing: ["_line_ending"], scanner: &scanner)
        #expect(result.name == "_line_ending")
        #expect(result.lexer.tokenEnd == definition.utf8.count)
    }

    @Test
    func `HTML name and attribute classes read Unicode scalars`() {
        var scanner = MarkdownExternalScanner()
        #expect(
            scan("<étiquette café=\"oui\">\n", allowing: ["_html_block_7_start"], scanner: &scanner).name
                == "_html_block_7_start")
        scanner = MarkdownExternalScanner()
        #expect(scan("<☃>\n", allowing: ["_html_block_7_start"], scanner: &scanner).name == nil)
    }

    @Test
    func `partial CDATA prefix falls through to a generic HTML tag`() {
        var scanner = MarkdownExternalScanner()
        #expect(
            scan("<![Cx>\n", allowing: ["_html_block_5_start", "_html_block_7_start"], scanner: &scanner).name
                == "_html_block_7_start")
    }

    @Test
    func `complete CDATA prefix stays unconsumed when its token is unavailable`() {
        var scanner = MarkdownExternalScanner()
        #expect(scan("<![CDATA[x>\n", allowing: ["_html_block_7_start"], scanner: &scanner).name == nil)
    }

    @Test
    func `indented chunk is suppressed when the grammar excludes it`() {
        var scanner = MarkdownExternalScanner()
        #expect(
            scan("    code\n", allowing: ["_indented_chunk_start", "_no_indented_chunk"], scanner: &scanner).name
                == nil)
    }

    @Test
    func `unoffered results decline without changing state`() {
        var scanner = MarkdownExternalScanner()
        var before: [UInt8] = []
        scanner.serialize(into: &before)
        #expect(scan("## heading\n", allowing: ["atx_h1_marker"], scanner: &scanner).name == nil)
        var after: [UInt8] = []
        scanner.serialize(into: &after)
        #expect(before == after)
        #expect(scan("# heading\n", allowing: [], scanner: &scanner).name == nil)
        #expect(scan("# heading\n", allowing: ["atx_h1_marker"], scanner: &scanner).name == "atx_h1_marker")
    }

    @Test
    func `serialization restores an open list and empty state resets it`() {
        var scanner = MarkdownExternalScanner()
        #expect(scan("- item\n", allowing: ["_list_marker_minus"], scanner: &scanner).name == "_list_marker_minus")
        var saved: [UInt8] = []
        scanner.serialize(into: &saved)
        #expect(saved.count <= maximumSerializedScannerStateSize)
        var restored = MarkdownExternalScanner()
        restored.deserialize(saved[...])
        var roundTrip: [UInt8] = []
        restored.serialize(into: &roundTrip)
        #expect(roundTrip == saved)
        #expect(scan("", allowing: ["_block_close"], scanner: &restored).name == "_block_close")
        restored.deserialize([])
        #expect(scan("", allowing: ["_block_close"], scanner: &restored).name == nil)
    }

    @Test
    func `malformed serialized block state resets safely`() {
        var scanner = MarkdownExternalScanner()
        scanner.deserialize([0, 1, 0, 0, 0][...])
        var state: [UInt8] = []
        scanner.serialize(into: &state)
        #expect(state == [0, 0, 0, 0, 0])
        scanner.deserialize([0, 0, 0, 0, 0, 255, 255, 255, 255][...])
        state.removeAll()
        scanner.serialize(into: &state)
        #expect(state == [0, 0, 0, 0, 0])
    }

    @Test
    func `block stack cannot exceed the serialized state limit`() {
        var scanner = MarkdownExternalScanner()
        for _ in 0 ..< 254 {
            #expect(scan("> ", allowing: ["_block_quote_start"], scanner: &scanner).name == "_block_quote_start")
        }
        var full: [UInt8] = []
        scanner.serialize(into: &full)
        #expect(full.count == 1021)
        #expect(full.count <= maximumSerializedScannerStateSize)
        #expect(scan("> ", allowing: ["_block_quote_start"], scanner: &scanner).name == nil)
        var after: [UInt8] = []
        scanner.serialize(into: &after)
        #expect(after == full)
    }

    @Test
    func `byte sized counters wrap as in the C scanner`() {
        var scanner = MarkdownExternalScanner()
        #expect(
            scan(
                String(repeating: "`", count: 256) + "\n", allowing: ["_fenced_code_block_start_backtick"],
                scanner: &scanner
            )
            .name == nil)
        #expect(
            scan(
                String(repeating: " ", count: 256) + "code\n", allowing: ["_indented_chunk_start"],
                scanner: &scanner
            )
            .name == nil)
        #expect(
            scan(
                "-" + String(repeating: " ", count: 256) + "item\n", allowing: ["_list_marker_minus"],
                scanner: &scanner
            )
            .name == nil)
    }
}
