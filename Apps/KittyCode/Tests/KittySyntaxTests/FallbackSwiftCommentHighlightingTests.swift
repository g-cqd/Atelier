import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import AtelierQuery
@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct FallbackSwiftCommentHighlightingTests {
    @Test
    func `Line comment is fully styled as comment not keyword`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine(
            "// this is a comment", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "// this is a comment")
        #expect(spans[0].style == commentStyle)
    }

    @Test
    func `Doc comment with keywords is fully styled as comment`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine(
            "/// if the read syscall fails, or", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "/// if the read syscall fails, or")
        #expect(spans[0].style == commentStyle)
    }

    @Test
    func `Keywords after comment line are still highlighted`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine(
            "    func read(into buffer: Int)", language: "swift", theme: theme)
        let funcSpan = spans.first { $0.text == "func" }
        #expect(funcSpan?.style == keywordStyle)
    }

    @Test
    func `Comment in middle of code line captures rest of line`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine(
            "let x = 1 // inline comment with if", language: "swift", theme: theme)
        let commentSpan = spans.last { $0.style == commentStyle }
        #expect(commentSpan != nil)
        #expect(commentSpan?.text == "// inline comment with if")
    }

    @Test
    func `Block comment is styled as comment`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let spans = LanguageHighlighter.highlightLine(
            "/* block if for while */", language: "swift", theme: theme)
        let commentSpan = spans.first { $0.style == commentStyle }
        #expect(commentSpan != nil)
        #expect(commentSpan?.text == "/* block if for while */")
    }

    @Test
    func `Keywords like protocol in regular comments are not highlighted as keywords`() {
        let theme = Theme.monokai
        let commentStyle = theme.style(for: "comment")
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine(
            "// Layer 4 — View protocol, layout", language: "swift", theme: theme)
        #expect(spans.count == 1)
        #expect(spans[0].style == commentStyle)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `override in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine(
            "/// Conforming types may override", language: "swift", theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `for in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine(
            "/// for zero-copy writes using `withUnsafeBufferPointer`.", language: "swift",
            theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }

    @Test
    func `is in doc comment is not highlighted as keyword`() {
        let theme = Theme.monokai
        let keywordStyle = theme.style(for: "keyword")
        let spans = LanguageHighlighter.highlightLine(
            "/// if the connection is at end-of-file.", language: "swift", theme: theme)
        #expect(!spans.contains { $0.style == keywordStyle })
    }
}
