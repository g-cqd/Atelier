import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Highlights inputs whose tree is deep enough to overflow the stack if it were freed recursively, which
/// `SyntaxTree`'s iterative `deinit` avoids.
@Suite
struct LargeFileHighlightTests {
    /// A long array of small objects, which the JSON grammar's right-recursive rules nest about as deep as the array
    /// is long.
    private func deeplyNestedJSON(elementCount: Int) -> String {
        var out = "["
        for index in 0 ..< elementCount {
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
