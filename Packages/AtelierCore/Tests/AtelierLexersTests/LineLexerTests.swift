import AtelierLexers
import AtelierSyntaxModel
import AtelierText
import Testing

/// Scanning a line at a time, each line from the state the last one ended in (P1a), gives each line the tokens the
/// whole-text scan gives it.
struct LineLexerTests {
    /// Every line of `text` scanned in order from ``LexState/initial``.
    static func lineScan(_ text: String, language: Language) -> LineTokens {
        let lines = TextLines(text)
        let lexer = LexicalLineLexer(language: language)
        var tokens: [LineToken] = []
        var offsets: [UInt32] = [0]
        var state = LexState.initial
        for line in 0 ..< lines.lineCount {
            state = lines.withLineBytes(at: line) { lexer.scan($0, from: state, into: &tokens) }
            offsets.append(UInt32(tokens.count))
        }
        return LineTokens(tokens: tokens, offsets: offsets)
    }

    /// The whole-text scan of `text`, cut at its lines.
    static func wholeScan(_ text: String, language: Language) -> LineTokens {
        let utf8 = text.utf8Span
        let tokens = LexicalHighlightEngine().highlight(utf8: utf8.span, language: language)
        return LineTokens(tokens, lineRanges: TextLines(text).lineRanges)
    }

    @Test(arguments: Language.allCases.filter { $0 != .plain })
    func `a line scan equals the whole-text scan on each language's corpus`(language: Language) {
        // LF line ends: a line lent without its `\r` would read an escape before a CRLF differently.
        let text = LexerCorpus.text(language, fragments: 400).replacing("\r\n", with: "\n")

        #expect(Self.lineScan(text, language: language) == Self.wholeScan(text, language: language))
    }

    @Test(arguments: [
        (Language.swift, ["let ", "x", "1.5", "/*", "*/", "\"", "\"\"\"", "#\"", "\"#", "\\", " ", "// c", "$0", "\n"]),
        (.python, ["def ", "x", "'", "\"", "'''", "\"\"\"", "\\", "# c", " ", "1", "\n"]),
        (.javascript, ["let ", "`", "${a}", "\"", "'", "/*", "*/", "\\", "//", " ", "\n"]),
        (.lua, ["local ", "--[[", "]]", "--", "\"", "'", "\\", "x", " ", "\n"]),
        (.rust, ["fn ", "/*", "*/", "\"", "'a", "\\", "r", " ", "\n"]),
        (.css, ["a", "{", "}", "b:", "/*", "*/", "\"", "'", "\\", ".c", "#fff", "1px", "//", " ", "\n"]),
        (
            .html,
            [
                "<a", " b=\"", "\"", "'", ">", "/>", "<!--", "-->", "<!x", "<script>", "</script>", "<style>",
                "</style>", "x", "&amp;", " ", "\n"
            ]
        )
    ])
    func `a line scan equals the whole-text scan on generated texts`(language: Language, pieces: [String]) {
        var random: UInt64 = 0x1E
        for _ in 0 ..< 400 {
            var text = ""
            for _ in 0 ..< 60 {
                random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += pieces[Int(random >> 33) % pieces.count]
            }
            // A final line break: a number that ends a text with a dot keeps the dot in a whole-text scan only.
            text += "\n"

            #expect(
                Self.lineScan(text, language: language) == Self.wholeScan(text, language: language),
                "\(text.debugDescription)")
        }
    }

    @Test
    func `a line inside a block comment or a string starts in its state and is coloured as one`() {
        let text = "a /* one\n/* two */ still\nend */ let x\nlet s = \"\"\"\nbody\n\"\"\"\n"

        let lines = Self.lineScan(text, language: .swift)

        #expect(lines[1].map(\.role) == [.comment])
        #expect(lines[1].map(\.range) == [0 ..< 15])
        #expect(lines[2].map(\.role) == [.comment, .keyword])
        #expect(lines[4].map(\.role) == [.string])
    }

    @Test
    func `a plain text has no tokens and keeps the initial state`() {
        var tokens: [LineToken] = []
        let bytes = Array("/* not a comment".utf8)
        let state = LexicalLineLexer(language: .plain).scan(bytes.span, from: .initial, into: &tokens)

        #expect(tokens.isEmpty)
        #expect(state == .initial)
    }
}
