import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Probes the syntax highlighter on inputs whose AST is deep enough to have
/// blown the thread stack via recursive struct-array deallocation before
/// `SyntaxTree` became a class with an iterative `deinit`. Synthesises the
/// payload at runtime so the test stays portable.
@Suite
struct LargeFileHighlightTests {

    /// Build a deeply-nested JSON payload that mirrors the structure that
    /// surfaced the SIGBUS — a long array of small objects, which the JSON
    /// grammar's right-recursive rules turn into an AST whose nesting depth
    /// approaches the array length.
    private func deeplyNestedJSON(elementCount: Int) -> String {
        var out = "["
        for index in 0..<elementCount {
            if index > 0 { out += "," }
            out += "{\"i\":\(index),\"v\":\"x\"}"
        }
        out += "]"
        return out
    }

    @Test
    func `synthetic deep JSON 5_000 elements highlights without crash`() async throws {
        let source = deeplyNestedJSON(elementCount: 5_000)
        _ = await LanguageHighlighter.ensureArtifacts(for: "json")
        let theme = Theme(defaultStyle: Style())
        let highlighted = LanguageHighlighter.highlightDocument(
            source: source, language: "json", theme: theme)
        #expect(!highlighted.isEmpty)
    }

    @Test
    func `synthetic deep JSON 10_000 elements highlights without crash`() async throws {
        let source = deeplyNestedJSON(elementCount: 10_000)
        _ = await LanguageHighlighter.ensureArtifacts(for: "json")
        let theme = Theme(defaultStyle: Style())
        let highlighted = LanguageHighlighter.highlightDocument(
            source: source, language: "json", theme: theme)
        #expect(!highlighted.isEmpty)
    }
}
