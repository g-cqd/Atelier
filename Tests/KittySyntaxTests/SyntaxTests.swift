import Testing
@testable import KittySyntax
@testable import KittyCodecs
@testable import KittyQuery
@testable import KittyParser

@Suite("Theme")
struct ThemeTests {
    @Test("Exact capture match")
    func exactMatch() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "keyword") == style)
    }

    @Test("Hierarchical fallback")
    func hierarchicalFallback() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        // keyword.function should fallback to keyword
        #expect(theme.style(for: "keyword.function") == style)
    }

    @Test("Default style fallback")
    func defaultFallback() {
        let theme = Theme(defaultStyle: Style(fg: .rgb(r: 128, g: 128, b: 128)))
        #expect(theme.style(for: "nonexistent") == theme.defaultStyle)
    }

    @Test("@ prefix is stripped")
    func prefixStripped() {
        var theme = Theme()
        let style = Style(bold: true)
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "@keyword") == style)
    }

    @Test("Monokai theme has common captures")
    func monokaiTheme() {
        let theme = Theme.monokai
        let kwStyle = theme.style(for: "keyword")
        #expect(kwStyle.bold)
    }
}

@Suite("Highlighter")
struct HighlighterTests {
    @Test("Highlight produces styled spans")
    func highlightSpans() {
        let highlighter = Highlighter(theme: .monokai)

        let node = SyntaxNode(type: "keyword", byteRange: 0..<3, isNamed: true)
        let root = SyntaxNode(type: "source", children: [node], byteRange: 0..<7)
        let tree = SyntaxTree(root: root, source: "let x =")

        let query = Query(patterns: [
            .nodeMatch(type: "keyword", children: [], capture: "keyword")
        ])

        let spans = highlighter.highlight(source: "let x =", tree: tree, query: query)
        #expect(!spans.isEmpty)
        // First span should be styled as keyword
        #expect(spans[0].style.bold)
    }
}

@Suite("GrammarRegistry")
struct GrammarRegistryTests {
    @Test("Register and lookup by extension")
    func registerLookup() {
        let registry = GrammarRegistry()
        registry.register(GrammarRegistry.LanguageEntry(
            name: "swift", extensions: [".swift"], path: "swift"
        ))
        let entry = registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test("Language names are sorted")
    func sortedNames() {
        let registry = GrammarRegistry()
        registry.register(GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        registry.register(GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        #expect(registry.languageNames == ["python", "swift"])
    }
}
