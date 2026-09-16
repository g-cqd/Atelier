import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

@Suite
struct HighlightTokenTests {
    @Test
    func `buildTokens produces tokens from query matches`() {
        let highlighter = Highlighter(theme: .monokai)

        let node = SyntaxNode(type: "keyword", byteRange: 0 ..< 3, isNamed: true)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0 ..< 7)
        let tree = SyntaxTree(root: root, source: "let x =")

        let query = Query(patterns: [
            .nodeMatch(type: "keyword", children: [], capture: "keyword")
        ])
        let matches = QueryMatcher.execute(query: query, tree: tree)
        let tokens = highlighter.buildTokens(matches: matches, layer: .structural)

        #expect(tokens.count == 1)
        #expect(tokens[0].role == .keyword)
        #expect(tokens[0].byteRange == 0 ..< 3)
        #expect(tokens[0].layer == .structural)
    }

    @Test
    func `tokensToSpans converts tokens to styled spans`() {
        let theme = Theme.monokai
        let highlighter = Highlighter(theme: theme)
        let resolver = RoleBasedThemeResolver(theme: theme)

        let tokens = [
            HighlightToken(byteRange: 0 ..< 3, role: .keyword, layer: .structural)
        ]

        let spans = highlighter.tokensToSpans(
            tokens: tokens, source: "let x =", resolver: resolver)
        #expect(spans.count == 2)
        #expect(spans[0].text == "let")
        #expect(spans[0].style.bold)
        #expect(spans[1].text == " x =")
    }

    @Test
    func `HighlightLayer ordering is correct`() {
        #expect(HighlightLayer.lexical < .structural)
        #expect(HighlightLayer.structural < .semantic)
    }

    @Test
    func `highlightDocument output is still valid after token path added`() async {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json")

        #expect(available)

        let source = #"{"key": "value"}"#
        let spans = session.highlightDocument(source: source)
        let allText = spans.flatMap { $0 }.map(\.text).joined()
        #expect(allText == source)
    }

    @Test
    func `Token priority matches span-path precedence for identical ranges`() {
        // Earlier patterns in query file should win on identical byte ranges.
        // This test mirrors the existing "Earlier identical-range captures override
        // later generic captures" test in HighlighterTests.

        var theme = Theme(defaultStyle: .default)
        let keyStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let stringStyle = Style(fg: .rgb(r: 4, g: 5, b: 6))
        theme.setStyle(keyStyle, for: "string.special")
        theme.setStyle(stringStyle, for: "string")

        let stringNode = SyntaxNode(type: "string", byteRange: 0 ..< 6, isNamed: true)
        let tree = SyntaxTree(
            root: SyntaxNode(type: "document", children: [stringNode], byteRange: 0 ..< 6),
            source: "\"name\""
        )

        // Pattern 0 = string.special.key (earlier, should win)
        // Pattern 1 = string (later, should lose)
        let query = Query(patterns: [
            .nodeMatch(type: "string", children: [], capture: "string.special.key"),
            .nodeMatch(type: "string", children: [], capture: "string")
        ])

        // Span path
        let spanResult = Highlighter(theme: theme)
            .highlight(
                source: tree.source, tree: tree, query: query)

        // Token path
        let highlighter = Highlighter(theme: theme)
        let matches = QueryMatcher.execute(query: query, tree: tree)
        let tokens = highlighter.buildTokens(matches: matches, layer: .structural)
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 6)
        let resolver = RoleBasedThemeResolver(theme: theme)
        let tokenResult = HighlightMerger.resolveToSpans(
            tokens: merged, source: tree.source, resolver: resolver, defaultStyle: theme.defaultStyle)

        // Both paths should produce the same style for the string
        #expect(spanResult.first?.style == keyStyle)
        #expect(tokenResult.first?.style == keyStyle)
    }

    @Test
    func `External-scanner grammar falls back to lexical not grammar-backed`() {
        // Python has externals — even if artifacts were cached, Session should
        // reject them because needsExternalScanner is true.
        // We don't call ensureArtifacts to avoid slow compilation; we just
        // verify that makeSession for Python is fallback-mode.
        let session = LanguageHighlighter.makeSession(language: "python")
        #expect(!session.isGrammarBacked)
        #expect(session.prefersLineInput)
    }
}
