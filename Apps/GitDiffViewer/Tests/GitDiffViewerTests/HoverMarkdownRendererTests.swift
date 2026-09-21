import Foundation
import Testing

@testable import DiffComparison

@Suite struct HoverMarkdownRendererTests {
    @Test func plainProseRendersItsText() {
        let attributed = renderHoverMarkdown("Adds two numbers.")
        #expect(String(attributed.characters) == "Adds two numbers.")
    }

    @Test func aFencedCodeBlockIsKeptVerbatim() {
        let attributed = renderHoverMarkdown("```swift\nfunc add(_ a: Int, _ b: Int) -> Int\n```")
        let text = String(attributed.characters)
        #expect(text == "func add(_ a: Int, _ b: Int) -> Int")
    }

    @Test func mixedProseAndCodeKeepsBothSections() {
        let markdown = "```swift\nfunc add(_ a: Int, _ b: Int) -> Int\n```\n\nAdds two numbers."
        let attributed = renderHoverMarkdown(markdown)
        let text = String(attributed.characters)
        #expect(text.contains("func add(_ a: Int, _ b: Int) -> Int"))
        #expect(text.contains("Adds two numbers."))
    }

    @Test func codeInsideAFenceIsNotInterpretedAsMarkdown() {
        // Underscores and asterisks in code must survive untouched, not turn into emphasis.
        let attributed = renderHoverMarkdown("```swift\nlet snake_case_name = *pointer\n```")
        let text = String(attributed.characters)
        #expect(text == "let snake_case_name = *pointer")
    }

    @Test func malformedMarkdownFallsBackToPlainText() {
        // An unterminated inline code span is invalid markdown syntax; the renderer must still show something
        // rather than nothing.
        let attributed = renderHoverMarkdown("Some `unterminated code span")
        let text = String(attributed.characters)
        #expect(text.contains("Some"))
        #expect(text.contains("unterminated code span"))
    }

    @Test func emptyMarkdownRendersEmpty() {
        let attributed = renderHoverMarkdown("")
        #expect(attributed.characters.isEmpty)
    }
}
