import Testing

@testable import AtelierSyntaxModel

struct HighlightTokenLinesTests {
    @Test
    func `a token spanning two lines is cut at the line break and rebased on each line`() {
        let tokens = [HighlightToken(byteRange: 0 ..< 9, role: .comment, layer: .lexical)]
        let byLine = HighlightToken.byLine(tokens, lineStarts: [0, 5], textLength: 11)
        #expect(
            byLine == [
                [HighlightToken(byteRange: 0 ..< 4, role: .comment, layer: .lexical)],
                [HighlightToken(byteRange: 0 ..< 4, role: .comment, layer: .lexical)]
            ])
    }

    @Test
    func `tokens land on their line and the line break itself carries none`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 3, role: .keyword), HighlightToken(byteRange: 4 ..< 5, role: .number),
            HighlightToken(byteRange: 6 ..< 8, role: .string, modifiers: [.deprecated], priority: 2)
        ]
        let byLine = HighlightToken.byLine(tokens, lineStarts: [0, 4, 6], textLength: 8)
        #expect(byLine[0] == [HighlightToken(byteRange: 0 ..< 3, role: .keyword)])
        #expect(byLine[1] == [HighlightToken(byteRange: 0 ..< 1, role: .number)])
        #expect(byLine[2] == [HighlightToken(byteRange: 0 ..< 2, role: .string, modifiers: [.deprecated], priority: 2)])
    }

    @Test
    func `no lines yields no rows and no tokens yields empty rows`() {
        #expect(HighlightToken.byLine([], lineStarts: [], textLength: 0).isEmpty)
        #expect(HighlightToken.byLine([], lineStarts: [0, 3], textLength: 5) == [[], []])
    }
}
