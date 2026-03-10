import Testing
import Foundation
@testable import KittySyntax
@testable import KittyCodecs
@testable import KittyGrammar
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

    @Test("LanguageHighlighter session matches one-shot grammar-backed highlighting")
    func sessionMatchesOneShotHighlighting() {
        let source = "import Foundation"
        let session = LanguageHighlighter.makeSession(language: "swift")

        #expect(session.highlightDocument(source: source) == LanguageHighlighter.highlightDocument(source: source, language: "swift"))
    }

    @Test("LanguageHighlighter session supports line-based fallback highlighting")
    func sessionSupportsLineBasedFallback() {
        let session = LanguageHighlighter.makeSession(language: nil)
        let lines = session.highlightLines(["// comment", "value"])

        #expect(session.prefersLineInput)
        #expect(lines.count == 2)
        #expect(lines[0].map(\.text).joined() == "// comment")
        #expect(lines[1].map(\.text).joined() == "value")
    }

    @Test("LanguageHighlighter prewarms only bundled grammar artifacts")
    func prewarmArtifacts() async {
        let warmed = await LanguageHighlighter.prewarmArtifacts(for: ["swift", "json", "swift", "unknown_lang"])

        #expect(warmed.contains("json"))
        #expect(!warmed.contains("swift"))
        #expect(!warmed.contains("unknown_lang"))
    }
}

@Suite("GrammarRegistry")
struct GrammarRegistryTests {
    @Test("Register and lookup by extension")
    func registerLookup() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(
            name: "swift", extensions: [".swift"], path: "swift"
        ))
        let entry = await registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test("Language names are sorted")
    func sortedNames() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        await registry.register(GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        let names = await registry.languageNames
        #expect(names == ["python", "swift"])
    }

    // MARK: - New tests

    @Test("entry(forExtension:) returns nil for unregistered extension")
    func entryForUnregisteredExtension() async {
        let registry = GrammarRegistry()
        let entry = await registry.entry(forExtension: ".xyz")
        #expect(entry == nil)
    }

    @Test("entry(forExtension:) normalises extension without leading dot")
    func entryNormalisesDotPrefix() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "json"))
        let entry = await registry.entry(forExtension: "json")
        #expect(entry?.name == "json")
    }

    @Test("loadManifest registers all 19 languages from bundled languages.json")
    func loadManifestRegistersAllLanguages() async throws {
        let grammarsPath = try #require(KittySyntaxResources.bundle.resourcePath)
        let manifestPath = "\(grammarsPath)/Grammars/languages.json"
        let registry = GrammarRegistry()
        try await registry.loadManifest(from: manifestPath)
        let names = await registry.languageNames
        #expect(names.count == 19)
    }
}

// MARK: - GrammarLoader (bundled grammar) tests

@Suite("GrammarLoader bundled grammar")
struct GrammarLoaderBundledTests {

    private func jsonGrammarPath() throws -> String {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        return "\(resourcePath)/Grammars/json/grammar.json"
    }

    @Test("Load bundled json/grammar.json — name is json")
    func loadBundledGrammarName() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "json")
    }

    @Test("Load bundled json/grammar.json — has expected rule names")
    func loadBundledGrammarRuleNames() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        let ruleNames = grammar.rules.map(\.name)
        let expectedNames = ["document", "_value", "object", "pair", "array", "string", "number", "true", "false", "null"]
        for name in expectedNames {
            #expect(ruleNames.contains(name), "Expected rule '\(name)' in grammar")
        }
    }

    @Test("Load bundled json/grammar.json — has 1 extra (whitespace pattern)")
    func loadBundledGrammarExtras() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.extras.count == 1)
    }

    @Test("Load bundled json/grammar.json — supertypes contains _value")
    func loadBundledGrammarSupertypes() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.supertypes.contains("_value"))
    }

    @Test("parse invalid JSON data throws GrammarError")
    func parseInvalidJSONThrows() {
        #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(Data("not valid json {{{".utf8))
        }
    }
}

// MARK: - Theme (Monokai) tests

@Suite("Theme Monokai")
struct ThemeMonokaiTests {

    @Test("Monokai returns non-default style for keyword")
    func monokaiKeywordIsNonDefault() {
        let style = Theme.monokai.style(for: "keyword")
        #expect(style != Style.default)
    }

    @Test("Monokai returns non-default style for string")
    func monokaiStringIsNonDefault() {
        let style = Theme.monokai.style(for: "string")
        #expect(style != Style.default)
    }

    @Test("Hierarchical fallback: keyword.function resolves to keyword style")
    func hierarchicalFallbackKeywordFunction() {
        let keywordStyle = Theme.monokai.style(for: "keyword")
        let keywordFunctionStyle = Theme.monokai.style(for: "keyword.function")
        // Monokai has no "keyword.function" entry so it falls back to "keyword"
        #expect(keywordFunctionStyle == keywordStyle)
    }

    @Test("style(for:) returns default style for nonexistent capture")
    func nonexistentCaptureReturnsDefault() {
        let style = Theme.monokai.style(for: "nonexistent_capture")
        #expect(style == Theme.monokai.defaultStyle)
    }
}

// MARK: - Highlighter additional tests

@Suite("Highlighter additional")
struct HighlighterAdditionalTests {

    @Test("Highlighting empty source returns single default-styled span")
    func emptySourceReturnsSingleDefaultSpan() {
        let highlighter = Highlighter(theme: .monokai)
        let root = SyntaxNode(type: "source", byteRange: 0..<0)
        let tree = SyntaxTree(root: root, source: "")
        let query = Query(patterns: [])
        let spans = highlighter.highlight(source: "", tree: tree, query: query)
        #expect(spans == [StyledSpan(text: "", style: Theme.monokai.defaultStyle)])
    }

    @Test("Highlighting with no query matches returns single default-styled span")
    func noMatchesReturnsSingleDefaultSpan() {
        let highlighter = Highlighter(theme: .monokai)
        let source = "hello"
        let root = SyntaxNode(type: "source", byteRange: 0..<5)
        let tree = SyntaxTree(root: root, source: source)
        // Pattern that matches "unknown_type" — will never match
        let query = Query(patterns: [
            .nodeMatch(type: "unknown_type", children: [], capture: "keyword")
        ])
        let spans = highlighter.highlight(source: source, tree: tree, query: query)
        #expect(spans == [StyledSpan(text: source, style: Theme.monokai.defaultStyle)])
    }

    @Test("Highlighting a string node produces a string-styled span")
    func stringNodeProducesStringStyledSpan() {
        var theme = Theme(defaultStyle: .default)
        let stringStyle = Style(fg: .rgb(r: 230, g: 219, b: 116))
        theme.setStyle(stringStyle, for: "string")

        let source = "\"hello\""  // 7 UTF-8 bytes
        let stringNode = SyntaxNode(type: "string", byteRange: 0..<7, isNamed: true)
        let root = SyntaxNode(type: "source", children: [stringNode], byteRange: 0..<7)
        let tree = SyntaxTree(root: root, source: source)
        let query = Query(patterns: [
            .nodeMatch(type: "string", children: [], capture: "string")
        ])

        let spans = Highlighter(theme: theme).highlight(source: source, tree: tree, query: query)
        #expect(spans == [StyledSpan(text: source, style: stringStyle)])
    }

    @Test("Highlighting two adjacent nodes produces two styled spans")
    func twoAdjacentNodesProduceTwoSpans() {
        var theme = Theme(defaultStyle: .default)
        let keywordStyle = Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true)
        let numberStyle = Style(fg: .rgb(r: 174, g: 129, b: 255))
        theme.setStyle(keywordStyle, for: "keyword")
        theme.setStyle(numberStyle, for: "number")

        // source: "if42" — 4 bytes
        let kwNode = SyntaxNode(type: "keyword", byteRange: 0..<2, isNamed: true)
        let numNode = SyntaxNode(type: "number", byteRange: 2..<4, isNamed: true)
        let root = SyntaxNode(type: "source", children: [kwNode, numNode], byteRange: 0..<4)
        let tree = SyntaxTree(root: root, source: "if42")
        let query = Query(patterns: [
            .nodeMatch(type: "keyword", children: [], capture: "keyword"),
            .nodeMatch(type: "number", children: [], capture: "number"),
        ])

        let spans = Highlighter(theme: theme).highlight(source: "if42", tree: tree, query: query)
        #expect(spans == [
            StyledSpan(text: "if", style: keywordStyle),
            StyledSpan(text: "42", style: numberStyle),
        ])
    }
}
