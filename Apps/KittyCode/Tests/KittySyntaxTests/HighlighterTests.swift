import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import AtelierQuery
@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct HighlighterTests {
    @Test
    func `Highlight produces styled spans`() {
        let highlighter = Highlighter(theme: .monokai)

        let node = SyntaxNode(type: "keyword", byteRange: 0 ..< 3, isNamed: true)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 7)
        let tree = SyntaxTree(root: root, source: "let x =")

        let query = Query(patterns: [
            .nodeMatch(type: "keyword", children: [], capture: "keyword")
        ])

        let spans = highlighter.highlight(source: "let x =", tree: tree, query: query)
        #expect(!spans.isEmpty)
        // First span should be styled as keyword
        #expect(spans[0].style.bold)
    }

    @Test
    func `Nested captures override broader captures`() {
        var theme = Theme(defaultStyle: .default)
        let functionStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let functionNameStyle = Style(fg: .rgb(r: 4, g: 5, b: 6), italic: true)
        let keywordStyle = Style(fg: .rgb(r: 7, g: 8, b: 9), bold: true)
        theme.setStyle(functionStyle, for: "function")
        theme.setStyle(functionNameStyle, for: "function.name")
        theme.setStyle(keywordStyle, for: "keyword")

        let identifier = SyntaxNode(type: "identifier", byteRange: 5 ..< 10, isNamed: true)
        let function = SyntaxNode(
            type: "function_definition",
            children: [identifier],
            byteRange: 0 ..< 20,
            isNamed: true
        )
        let keyword = SyntaxNode(type: "keyword", byteRange: 20 ..< 23, isNamed: true)
        let root = SyntaxNode(
            type: "source",
            children: [function, keyword],
            byteRange: 0 ..< 23
        )
        let tree = SyntaxTree(root: root, source: "abcdefghijklmnopqrstuvw")
        let query = Query(patterns: [
            .nodeMatch(type: "function_definition", children: [], capture: "function"),
            .nodeMatch(type: "identifier", children: [], capture: "function.name"),
            .nodeMatch(type: "keyword", children: [], capture: "keyword")
        ])

        let spans = Highlighter(theme: theme)
            .highlight(
                source: tree.source,
                tree: tree,
                query: query
            )

        #expect(
            spans == [
                StyledSpan(text: "abcde", style: functionStyle),
                StyledSpan(text: "fghij", style: functionNameStyle),
                StyledSpan(text: "klmnopqrst", style: functionStyle),
                StyledSpan(text: "uvw", style: keywordStyle)
            ])
    }

    @Test
    func `Earlier identical-range captures override later generic captures`() {
        var theme = Theme(defaultStyle: .default)
        let keyStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let stringStyle = Style(fg: .rgb(r: 4, g: 5, b: 6))
        theme.setStyle(keyStyle, for: "string.special.key")
        theme.setStyle(stringStyle, for: "string")

        let stringNode = SyntaxNode(type: "string", byteRange: 0 ..< 6, isNamed: true)
        let tree = SyntaxTree(
            root: SyntaxNode(type: "document", children: [stringNode], byteRange: 0 ..< 6),
            source: "\"name\""
        )
        let query = Query(patterns: [
            .nodeMatch(type: "string", children: [], capture: "string.special.key"),
            .nodeMatch(type: "string", children: [], capture: "string")
        ])

        let spans = Highlighter(theme: theme)
            .highlight(
                source: tree.source,
                tree: tree,
                query: query
            )

        #expect(spans == [StyledSpan(text: "\"name\"", style: keyStyle)])
    }

    @Test
    func `LanguageHighlighter session matches one-shot grammar-backed highlighting`() async {
        let source = "true"
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json")

        #expect(available)
        #expect(session.isGrammarBacked)
        #expect(
            session.highlightDocument(source: source)
                == LanguageHighlighter.highlightDocument(source: source, language: "json"))
    }

    @Test
    func `LanguageHighlighter session supports line-based fallback highlighting`() {
        let session = LanguageHighlighter.makeSession(language: nil)
        let lines = session.highlightLines(["// comment", "value"])

        #expect(session.prefersLineInput)
        #expect(lines.count == 2)
        #expect(lines[0].map(\.text).joined() == "// comment")
        #expect(lines[1].map(\.text).joined() == "value")
    }

    @Test
    func `LanguageHighlighter prewarms bundled grammar artifacts used by kittycode`() async {
        let warmed = await LanguageHighlighter.prewarmArtifacts(for: ["json", "unknown_lang"])

        #expect(warmed.contains("json"))
        #expect(!warmed.contains("unknown_lang"))
    }

    @Test
    func `Bundled language manifest drives runtime language detection`() {
        #expect(LanguageHighlighter.detectLanguage(for: "main.SWIFT") == "swift")
        #expect(LanguageHighlighter.detectLanguage(for: "settings.yaml") == "yaml")
        #expect(LanguageHighlighter.detectLanguage(for: "Makefile") == nil)
    }

    /// The bundled JSON grammar parses an object to a bare `_start` node today (g-cqd/Atelier#2), so the session
    /// drops to the lexical tier, which tells keys from string values on its own.
    @Test
    func `json keys stay distinct from string values through the lexical tier`() async {
        var theme = Theme(defaultStyle: .default)
        let keyStyle = Style(fg: .rgb(r: 10, g: 20, b: 30))
        let stringStyle = Style(fg: .rgb(r: 40, g: 50, b: 60))
        let numberStyle = Style(fg: .rgb(r: 70, g: 80, b: 90))
        let literalStyle = Style(fg: .rgb(r: 100, g: 110, b: 120))
        theme.setStyle(keyStyle, for: "property")
        theme.setStyle(stringStyle, for: "string")
        theme.setStyle(numberStyle, for: "number")
        theme.setStyle(literalStyle, for: "keyword")

        let source = #"{"name":"value","count":42,"enabled":true}"#
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json", theme: theme)
        let spans = session.highlightDocument(source: source).flatMap { $0 }

        #expect(available)
        #expect(!session.isGrammarBacked)
        #expect(spans.first(where: { $0.text == "\"name\"" })?.style == keyStyle)
        #expect(spans.first(where: { $0.text == "\"value\"" })?.style == stringStyle)
        #expect(spans.first(where: { $0.text == "42" })?.style == numberStyle)
        #expect(spans.first(where: { $0.text == "true" })?.style == literalStyle)
    }
}
