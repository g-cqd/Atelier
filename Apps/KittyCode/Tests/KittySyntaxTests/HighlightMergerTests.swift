import Testing

@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct HighlightMergerTests {
    @Test
    func `Non-overlapping tokens pass through unchanged`() {
        let tokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .structural),
            HighlightToken(byteRange: 4..<7, role: .string, layer: .structural),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 10)
        #expect(merged.count == 2)
        #expect(merged[0].byteRange == 0..<3)
        #expect(merged[0].role == .keyword)
        #expect(merged[1].byteRange == 4..<7)
        #expect(merged[1].role == .string)
    }

    @Test
    func `Higher layer wins on overlap`() {
        let tokens = [
            HighlightToken(byteRange: 0..<5, role: .variable, layer: .structural),
            HighlightToken(byteRange: 0..<5, role: .function, layer: .semantic),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 5)
        #expect(merged.count == 1)
        #expect(merged[0].role == .function)
        #expect(merged[0].byteRange == 0..<5)
    }

    @Test
    func `Higher priority wins within same layer`() {
        let tokens = [
            HighlightToken(byteRange: 0..<10, role: .variable, layer: .structural, priority: 0),
            HighlightToken(byteRange: 2..<5, role: .keyword, layer: .structural, priority: 1),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 10)
        #expect(merged.count == 3)
        #expect(merged[0].role == .variable)
        #expect(merged[0].byteRange == 0..<2)
        #expect(merged[1].role == .keyword)
        #expect(merged[1].byteRange == 2..<5)
        #expect(merged[2].role == .variable)
        #expect(merged[2].byteRange == 5..<10)
    }

    @Test
    func `Narrower range wins at same layer and priority`() {
        let tokens = [
            HighlightToken(byteRange: 0..<10, role: .function, layer: .structural, priority: 0),
            HighlightToken(byteRange: 3..<6, role: .variable, layer: .structural, priority: 0),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 10)
        #expect(merged.count == 3)
        #expect(merged[1].role == .variable)
    }

    @Test
    func `Empty input produces empty output`() {
        let merged = HighlightMerger.merge([], sourceByteCount: 10)
        #expect(merged.isEmpty)
    }

    @Test
    func `resolveToSpans fills gaps with default style`() {
        let tokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .structural),
        ]
        let theme = Theme.monokai
        let resolver = RoleBasedThemeResolver(theme: theme)
        let spans = HighlightMerger.resolveToSpans(
            tokens: tokens,
            source: "let x = 1",
            resolver: resolver,
            defaultStyle: theme.defaultStyle
        )
        #expect(spans.count == 2)
        #expect(spans[0].text == "let")
        #expect(spans[1].text == " x = 1")
        #expect(spans[1].style == theme.defaultStyle)
    }

    @Test
    func `Lexical tokens provide baseline under structural tokens`() {
        // Lexical covers entire range, structural refines a subset
        let tokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .lexical, priority: 0),
            HighlightToken(byteRange: 4..<7, role: .string, layer: .lexical, priority: 0),
            HighlightToken(byteRange: 0..<3, role: .keywordFunction, layer: .structural, priority: 0),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 10)

        // Structural overrides lexical for 0..<3
        let first = merged.first(where: { $0.byteRange.lowerBound == 0 })
        #expect(first?.role == .keywordFunction)

        // Lexical remains for 4..<7 (no structural override)
        let second = merged.first(where: { $0.byteRange.lowerBound == 4 })
        #expect(second?.role == .string)
    }

    @Test
    func `Semantic overrides both structural and lexical`() {
        let tokens = [
            HighlightToken(byteRange: 0..<5, role: .keyword, layer: .lexical),
            HighlightToken(byteRange: 0..<5, role: .variable, layer: .structural),
            HighlightToken(byteRange: 0..<5, role: .function, layer: .semantic),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 5)
        #expect(merged.count == 1)
        #expect(merged[0].role == .function)
    }
}
