import Testing
import Foundation
@testable import KittySyntax
@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyQuery
@testable import KittyParser

@Suite
struct ThemeTests {
    @Test
    func `Exact capture match`() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "keyword") == style)
    }

    @Test
    func `Hierarchical fallback`() {
        var theme = Theme()
        let style = Style(fg: .rgb(r: 255, g: 0, b: 0))
        theme.setStyle(style, for: "keyword")
        // keyword.function should fallback to keyword
        #expect(theme.style(for: "keyword.function") == style)
    }

    @Test
    func `Default style fallback`() {
        let theme = Theme(defaultStyle: Style(fg: .rgb(r: 128, g: 128, b: 128)))
        #expect(theme.style(for: "nonexistent") == theme.defaultStyle)
    }

    @Test
    func `at prefix is stripped`() {
        var theme = Theme()
        let style = Style(bold: true)
        theme.setStyle(style, for: "keyword")
        #expect(theme.style(for: "@keyword") == style)
    }

    @Test
    func `Monokai theme has common captures`() {
        let theme = Theme.monokai
        let kwStyle = theme.style(for: "keyword")
        #expect(kwStyle.bold)
    }
}

@Suite
struct HighlighterTests {
    @Test
    func `Highlight produces styled spans`() {
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

    @Test
    func `Nested captures override broader captures`() {
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

    @Test
    func `Earlier identical-range captures override later generic captures`() {
        var theme = Theme(defaultStyle: .default)
        let keyStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let stringStyle = Style(fg: .rgb(r: 4, g: 5, b: 6))
        theme.setStyle(keyStyle, for: "string.special.key")
        theme.setStyle(stringStyle, for: "string")

        let stringNode = SyntaxNode(type: "string", byteRange: 0..<6, isNamed: true)
        let tree = SyntaxTree(
            root: SyntaxNode(type: "document", children: [stringNode], byteRange: 0..<6),
            source: "\"name\""
        )
        let query = Query(patterns: [
            .nodeMatch(type: "string", children: [], capture: "string.special.key"),
            .nodeMatch(type: "string", children: [], capture: "string"),
        ])

        let spans = Highlighter(theme: theme).highlight(
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
        #expect(session.highlightDocument(source: source) == LanguageHighlighter.highlightDocument(source: source, language: "json"))
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

    @Test
    func `Grammar-backed json highlighting keeps object keys distinct from string values`() async {
        var theme = Theme(defaultStyle: .default)
        let keyStyle = Style(fg: .rgb(r: 10, g: 20, b: 30))
        let stringStyle = Style(fg: .rgb(r: 40, g: 50, b: 60))
        let numberStyle = Style(fg: .rgb(r: 70, g: 80, b: 90))
        let constantStyle = Style(fg: .rgb(r: 100, g: 110, b: 120))
        theme.setStyle(keyStyle, for: "string.special")
        theme.setStyle(stringStyle, for: "string")
        theme.setStyle(numberStyle, for: "number")
        theme.setStyle(constantStyle, for: "constant.builtin")

        let source = #"{"name":"value","count":42,"enabled":true}"#
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json", theme: theme)
        let spans = session.highlightDocument(source: source).flatMap { $0 }

        #expect(available)
        #expect(spans.first(where: { $0.text == "\"name\"" })?.style == keyStyle)
        #expect(spans.first(where: { $0.text == "\"value\"" })?.style == stringStyle)
        #expect(spans.first(where: { $0.text == "42" })?.style == numberStyle)
        #expect(spans.first(where: { $0.text == "true" })?.style == constantStyle)
    }
}

@Suite
struct FallbackSwiftCommentHighlightingTests {
    @Test
    func `Line comment is fully styled as comment not keyword`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine("// this is a comment", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "// this is a comment")
        #expect(spans[0].style == commentStyle)
    }

    @Test
    func `Doc comment with keywords is fully styled as comment`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine("/// if the read syscall fails, or", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "/// if the read syscall fails, or")
        #expect(spans[0].style == commentStyle)
    }

    @Test
    func `Keywords after comment line are still highlighted`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine("    func read(into buffer: Int)", language: "swift", theme: theme)
        let funcSpan = spans.first { $0.text == "func" }
        #expect(funcSpan?.style == keywordStyle)
    }

    @Test
    func `Comment in middle of code line captures rest of line`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine("let x = 1 // inline comment with if", language: "swift", theme: theme)
        let commentSpan = spans.last { $0.style == commentStyle }
        #expect(commentSpan != nil)
        #expect(commentSpan?.text == "// inline comment with if")
    }

    @Test
    func `Block comment is styled as comment`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine("/* block if for while */", language: "swift", theme: theme)
        let commentSpan = spans.first { $0.style == commentStyle }
        #expect(commentSpan != nil)
        #expect(commentSpan?.text == "/* block if for while */")
    }

    @Test
    func `Keywords like protocol in regular comments are not highlighted as keywords`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine("// Layer 4 — View protocol, layout", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].style == commentStyle)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `override in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine("/// Conforming types may override", language: "swift", theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `for in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine("/// for zero-copy writes using `withUnsafeBufferPointer`.", language: "swift", theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `is in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine("/// if the connection is at end-of-file.", language: "swift", theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }
}

@Suite
struct GrammarRegistryTests {
    @Test
    func `Register and lookup by extension`() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(
            name: "swift", extensions: [".swift"], path: "swift"
        ))
        let entry = await registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test
    func `Language names are sorted`() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        await registry.register(GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        let names = await registry.languageNames
        #expect(names == ["python", "swift"])
    }

    // MARK: - New tests

    @Test
    func `entry forExtension returns nil for unregistered extension`() async {
        let registry = GrammarRegistry()
        let entry = await registry.entry(forExtension: ".xyz")
        #expect(entry == nil)
    }

    @Test
    func `entry forExtension normalises extension without leading dot`() async {
        let registry = GrammarRegistry()
        await registry.register(GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "json"))
        let entry = await registry.entry(forExtension: "json")
        #expect(entry?.name == "json")
    }

    @Test
    func `loadManifest registers all 19 languages from bundled languages json`() async throws {
        let grammarsPath = try #require(KittySyntaxResources.bundle.resourcePath)
        let manifestPath = "\(grammarsPath)/Grammars/languages.json"
        let registry = GrammarRegistry()
        try await registry.loadManifest(from: manifestPath)
        let names = await registry.languageNames
        #expect(names.count == 19)
    }

    @Test
    func `Bundled manifest entries ship grammar and highlight resources`() throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)

        for entry in BundledLanguageManifest.entries {
            let grammarPath = "\(resourcePath)/Grammars/\(entry.path)/grammar.json"
            let highlightsPath = "\(resourcePath)/Grammars/\(entry.path)/highlights.scm"

            #expect(FileManager.default.fileExists(atPath: grammarPath), "Missing grammar for \(entry.name)")
            #expect(FileManager.default.fileExists(atPath: highlightsPath), "Missing highlights for \(entry.name)")
        }
    }
}

// MARK: - GrammarLoader (bundled grammar) tests

@Suite
struct GrammarLoaderBundledGrammarTests {

    private func jsonGrammarPath() throws -> String {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        return "\(resourcePath)/Grammars/json/grammar.json"
    }

    @Test
    func `Load bundled json grammar json name is json`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "json")
    }

    @Test
    func `Load bundled json grammar json has expected rule names`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        let ruleNames = grammar.rules.map(\.name)
        let expectedNames = ["document", "_value", "object", "pair", "array", "string", "number", "true", "false", "null"]
        for name in expectedNames {
            #expect(ruleNames.contains(name), "Expected rule '\(name)' in grammar")
        }
    }

    @Test
    func `Load bundled json grammar json has 2 extras whitespace pattern plus comment`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.extras.count == 2)
    }

    @Test
    func `Load bundled json grammar json supertypes contains _value`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.supertypes.contains("_value"))
    }

    @Test
    func `parse invalid JSON data throws GrammarError`() {
        #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(Data("not valid json {{{".utf8))
        }
    }

    @Test
    func `Load bundled swift grammar external scanner is not required`() throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let path = "\(resourcePath)/Grammars/swift/grammar.json"
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "swift")
        #expect(grammar.externals.isEmpty)
    }
}

// MARK: - Theme (Monokai) tests

@Suite
struct ThemeMonokaiTests {

    @Test
    func `Monokai returns non-default style for keyword`() {
        let style = Theme.monokai.style(for: "keyword")
        #expect(style != Style.default)
    }

    @Test
    func `Monokai returns non-default style for string`() {
        let style = Theme.monokai.style(for: "string")
        #expect(style != Style.default)
    }

    @Test
    func `Hierarchical fallback keyword function resolves to keyword style`() {
        let keywordStyle = Theme.monokai.style(for: "keyword")
        let keywordFunctionStyle = Theme.monokai.style(for: "keyword.function")
        // Monokai has no "keyword.function" entry so it falls back to "keyword"
        #expect(keywordFunctionStyle == keywordStyle)
    }

    @Test
    func `style for returns default style for nonexistent capture`() {
        let style = Theme.monokai.style(for: "nonexistent_capture")
        #expect(style == Theme.monokai.defaultStyle)
    }
}

// MARK: - Highlighter additional tests

@Suite
struct HighlighterAdditionalTests {

    @Test
    func `Highlighting empty source returns single default-styled span`() {
        let highlighter = Highlighter(theme: .monokai)
        let root = SyntaxNode(type: "source", byteRange: 0..<0)
        let tree = SyntaxTree(root: root, source: "")
        let query = Query(patterns: [])
        let spans = highlighter.highlight(source: "", tree: tree, query: query)
        #expect(spans == [StyledSpan(text: "", style: Theme.monokai.defaultStyle)])
    }

    @Test
    func `Highlighting with no query matches returns single default-styled span`() {
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

    @Test
    func `Highlighting a string node produces a string-styled span`() {
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

    @Test
    func `Highlighting two adjacent nodes produces two styled spans`() {
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
