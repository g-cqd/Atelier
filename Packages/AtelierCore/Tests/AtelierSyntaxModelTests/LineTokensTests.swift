import Testing

@testable import AtelierSyntaxModel

struct LineTokensTests {
    @Test
    func `flat per-line tokens equal byLine on a token that spans lines and on the line breaks`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 9, role: .comment, layer: .lexical),
            HighlightToken(byteRange: 9 ..< 11, role: .keyword),
            HighlightToken(byteRange: 11 ..< 12, role: .operator),
            HighlightToken(byteRange: 14 ..< 17, role: .string, modifiers: [.deprecated], priority: 2)
        ]
        let lineStarts = [0, 5, 12, 13]
        let lines = LineTokens(tokens, lineStarts: lineStarts, textLength: 17)
        #expect(lines.map(Array.init) == HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: 17))
        #expect(lines.count == 4)
        #expect(lines[2].isEmpty)
    }

    @Test
    func `flat per-line tokens equal byLine on generated texts`() {
        var random = SplitMix64(seed: 0x3A6)
        for _ in 0 ..< 500 {
            let (tokens, lineStarts, textLength) = Self.generated(&random)
            let expected = HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: textLength)
            let lines = LineTokens(tokens, lineStarts: lineStarts, textLength: textLength)
            #expect(lines.map(Array.init) == expected)
            #expect(lines.tokens == expected.flatMap(\.self))
        }
    }

    @Test
    func `no lines has no rows, and no tokens has empty rows`() {
        #expect(LineTokens([], lineStarts: [], textLength: 0).isEmpty)
        #expect(LineTokens([], lineStarts: [0, 3], textLength: 5).map(Array.init) == [[], []])
        #expect(LineTokens(emptyLines: 3) == LineTokens([], lineStarts: [0, 1, 2], textLength: 2))
    }

    @Test
    func `a line range ends a token where the line's text does, before a carriage return`() {
        // "ab\r\ncd": a comment from 0 runs through the `\r`; the first line's text is 0 ..< 2.
        let tokens = [
            HighlightToken(byteRange: 0 ..< 3, role: .comment), HighlightToken(byteRange: 2 ..< 3, role: .string),
            HighlightToken(byteRange: 4 ..< 6, role: .number)
        ]
        let lines = LineTokens([tokens[0], tokens[2]], lineRanges: [0 ..< 2, 4 ..< 6])
        #expect(lines[0] == [HighlightToken(byteRange: 0 ..< 2, role: .comment)])
        #expect(lines[1] == [HighlightToken(byteRange: 0 ..< 2, role: .number)])
        let dropped = LineTokens([tokens[1], tokens[2]], lineRanges: [0 ..< 2, 4 ..< 6])
        #expect(dropped[0].isEmpty)
        #expect(dropped.tokenIndices(ofLine: 1) == 0 ..< 1)
    }

    /// Random ascending, disjoint tokens over a random text of short lines, some empty.
    private static func generated(_ random: inout SplitMix64) -> ([HighlightToken], [Int], Int) {
        let lineCount = Int(random.next() % 12)
        var lineStarts: [Int] = []
        var position = 0
        for _ in 0 ..< lineCount {
            lineStarts.append(position)
            position += Int(random.next() % 7) + 1  // the line's text, then its line break
        }
        let textLength = max(position - (lineCount > 0 ? 1 : 0) + Int(random.next() % 2), 0)
        var tokens: [HighlightToken] = []
        var cursor = 0
        while cursor < textLength {
            cursor += Int(random.next() % 3)
            let length = Int(random.next() % 9) + 1
            guard cursor + length <= textLength else { break }
            let role = HighlightRole.allCases[Int(random.next() % UInt64(HighlightRole.allCases.count))]
            tokens.append(
                HighlightToken(
                    byteRange: cursor ..< cursor + length, role: role, modifiers: [.readonly],
                    layer: .lexical, priority: Int(random.next() % 3)))
            cursor += length
        }
        return (tokens, lineStarts, textLength)
    }
}

/// A seeded generator, so a failing case reproduces.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
