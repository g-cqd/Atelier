import Testing

@testable import AtelierSyntaxModel

/// The merger's precedence: layer first, then width (the narrower token wins), then priority.
struct HighlightMergerOrderTests {
    @Test
    func `a semantic token over a lexical one wins, however narrow the lexical one`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 10, role: .variable, layer: .semantic),
            HighlightToken(byteRange: 2 ..< 5, role: .keyword, layer: .lexical)
        ]
        #expect(
            HighlightMerger.merge(tokens, sourceByteCount: 10) == [
                HighlightToken(byteRange: 0 ..< 10, role: .variable, layer: .semantic)
            ])
    }

    @Test
    func `identical ranges keep the earlier pattern, which has the higher priority`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 4, role: .stringSpecial, priority: 0),
            HighlightToken(byteRange: 0 ..< 4, role: .string, priority: 1)
        ]
        #expect(
            HighlightMerger.merge(tokens, sourceByteCount: 4) == [
                HighlightToken(byteRange: 0 ..< 4, role: .string, priority: 1)
            ])
    }

    @Test
    func `a narrower token of the same layer shows through a wider one of higher priority`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 6, role: .string, priority: 3),
            HighlightToken(byteRange: 2 ..< 4, role: .escape, priority: 0)
        ]
        #expect(
            HighlightMerger.merge(tokens, sourceByteCount: 6) == [
                HighlightToken(byteRange: 0 ..< 2, role: .string, priority: 3),
                HighlightToken(byteRange: 2 ..< 4, role: .escape, priority: 0),
                HighlightToken(byteRange: 4 ..< 6, role: .string, priority: 3)
            ])
    }
}
