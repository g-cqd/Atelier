import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

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
