import AtelierSyntaxModel
import AtelierTheme
import KittyStyle
import Testing

@testable import KittySyntax

/// The lexical tier of the shared engine standing in for a grammar: the path the editor renders with.
struct LexicalFallbackTests {
    private let theme = Theme.monokai

    private func session(_ language: String?) -> LanguageHighlighter.Session {
        LanguageHighlighter.makeSession(language: language, theme: theme, preferGrammar: false)
    }

    @Test
    func `a language without a grammar is scanned by the shared lexers`() {
        let spans = LanguageHighlighter.highlightLine("fn main() {} // c", language: "rust", theme: theme)
        #expect(spans.map(\.text) == ["fn", " main() {} ", "// c"])
        #expect(spans.map(\.style) == [theme.style(for: "keyword"), theme.defaultStyle, theme.style(for: "comment")])
    }

    @Test
    func `a block comment opened on one line styles the lines it spans`() {
        let lines = session("swift").highlightDocument(source: "/* open\nstill\n*/ let x")
        let comment = theme.style(for: "comment")
        #expect(lines.count == 3)
        #expect(lines[0] == [StyledSpan(text: "/* open", style: comment)])
        #expect(lines[1] == [StyledSpan(text: "still", style: comment)])
        #expect(lines[2].first == StyledSpan(text: "*/", style: comment))
        #expect(lines[2].contains(StyledSpan(text: "let", style: theme.style(for: "keyword"))))
    }

    @Test
    func `a document yields one span array per line and an empty line has none`() {
        let lines = session("swift").highlightDocument(source: "let a = 1\n\nlet b\n")
        #expect(lines.count == 4)
        #expect(lines[1].isEmpty)
        #expect(lines[3].isEmpty)
        #expect(session("swift").highlightDocument(source: "").count == 1)
        #expect(session("swift").highlightLines([String]()).count == 1)
    }

    @Test
    func `the viewport returns exactly the visible lines`() {
        let source = "let a = 1\nlet b = 2\nlet c = 3\nlet d = 4\n"
        let lines = session("swift").highlightViewport(source: source, visibleLineRange: 1 ..< 3)
        #expect(lines.count == 2)
        #expect(lines.map { $0.map(\.text).joined() } == ["let b = 2", "let c = 3"])
    }

    @Test
    func `an unknown language is plain text in the default style`() {
        let spans = LanguageHighlighter.highlightLine("let x // c", language: "brainfuck", theme: theme)
        #expect(spans == [StyledSpan(text: "let x // c", style: theme.defaultStyle)])
        #expect(LanguageHighlighter.highlightLine("", language: nil, theme: theme).isEmpty)
    }

    @Test
    func `the terminal theme mirrors the shared theme through the role hierarchy`() {
        let keyword = theme.style(for: "keyword")
        #expect(keyword == Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true))
        #expect(theme.style(for: "keyword.function") == keyword)
        #expect(theme.style(for: "comment.documentation").underline == .single)
        #expect(theme.defaultStyle == Style(fg: .rgb(r: 248, g: 248, b: 242)))
        let resolver = RoleBasedThemeResolver(theme: theme)
        #expect(resolver.resolve(role: .keywordFunction) == keyword)
    }

    @Test
    func `a theme style converts to a terminal style channel by channel`() {
        let style = ThemeStyle(
            foreground: ThemeColor(red: 1, green: 0, blue: 0.5), background: ThemeColor(byteRed: 1, green: 2, blue: 3),
            isBold: true, isItalic: true, isUnderlined: true, isStruckThrough: true)
        #expect(
            Style(style)
                == Style(
                    fg: .rgb(r: 255, g: 0, b: 128), bg: .rgb(r: 1, g: 2, b: 3), bold: true, italic: true,
                    underline: .single, strikethrough: true))
        #expect(Style(ThemeStyle()) == Style())
    }
}
