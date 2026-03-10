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

    @Test("Nested captures override broader captures")
    func nestedCapturesOverrideBroaderCaptures() {
        var theme = Theme(defaultStyle: .default)
        let functionStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let functionNameStyle = Style(fg: .rgb(r: 4, g: 5, b: 6), italic: true)
        let keywordStyle = Style(fg: .rgb(r: 7, g: 8, b: 9), bold: true)
        theme.setStyle(functionStyle, for: "function")
        theme.setStyle(functionNameStyle, for: "function.name")
        theme.setStyle(keywordStyle, for: "keyword")

        let identifier = SyntaxNode(type: "identifier", byteRange: 5..<10, isNamed: true)
        let function = SyntaxNode(
            type: "function_definition",
            children: [identifier],
            byteRange: 0..<20,
            isNamed: true
        )
        let keyword = SyntaxNode(type: "keyword", byteRange: 20..<23, isNamed: true)
        let root = SyntaxNode(
            type: "source",
            children: [function, keyword],
            byteRange: 0..<23
        )
        let tree = SyntaxTree(root: root, source: "abcdefghijklmnopqrstuvw")
        let query = Query(patterns: [
            .nodeMatch(type: "function_definition", children: [], capture: "function"),
            .nodeMatch(type: "identifier", children: [], capture: "function.name"),
            .nodeMatch(type: "keyword", children: [], capture: "keyword"),
        ])

        let spans = Highlighter(theme: theme).highlight(
            source: tree.source,
            tree: tree,
            query: query
        )

        #expect(spans == [
            StyledSpan(text: "abcde", style: functionStyle),
            StyledSpan(text: "fghij", style: functionNameStyle),
            StyledSpan(text: "klmnopqrst", style: functionStyle),
            StyledSpan(text: "uvw", style: keywordStyle),
        ])
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
