import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

@Suite
struct HighlighterAdditionalTests {
    @Test
    func `Highlighting empty source returns single default-styled span`() {
        let highlighter = Highlighter(theme: .monokai)
        let root = SyntaxNode(type: "source", byteRange: 0 ..< 0)
        let tree = SyntaxTree(root: root, source: "")
        let query = Query(patterns: [])
        let spans = highlighter.highlight(source: "", tree: tree, query: query)
        #expect(spans == [StyledSpan(text: "", style: Theme.monokai.defaultStyle)])
    }

    @Test
    func `Highlighting with no query matches returns single default-styled span`() {
        let highlighter = Highlighter(theme: .monokai)
        let source = "hello"
        let root = SyntaxNode(type: "source", byteRange: 0 ..< 5)
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
        let stringNode = SyntaxNode(type: "string", byteRange: 0 ..< 7, isNamed: true)
        let root = SyntaxNode(type: "source", children: [stringNode], byteRange: 0 ..< 7)
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
        let kwNode = SyntaxNode(type: "keyword", byteRange: 0 ..< 2, isNamed: true)
        let numNode = SyntaxNode(type: "number", byteRange: 2 ..< 4, isNamed: true)
        let root = SyntaxNode(type: "source", children: [kwNode, numNode], byteRange: 0 ..< 4)
        let tree = SyntaxTree(root: root, source: "if42")
        let query = Query(patterns: [
            .nodeMatch(type: "keyword", children: [], capture: "keyword"),
            .nodeMatch(type: "number", children: [], capture: "number")
        ])

        let spans = Highlighter(theme: theme).highlight(source: "if42", tree: tree, query: query)
        #expect(
            spans == [
                StyledSpan(text: "if", style: keywordStyle),
                StyledSpan(text: "42", style: numberStyle)
            ])
    }
}
