import AemiTestKit
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
        let expected = Self.lineTokens(HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: 17))
        #expect(lines.map(Array.init) == expected)
        #expect(lines.count == 4)
        #expect(lines[2].isEmpty)
    }

    @Test
    func `flat per-line tokens equal byLine on generated texts`() {
        var random = SeededRNG(seed: 0x3A6)
        for _ in 0 ..< 500 {
            let (tokens, lineStarts, textLength) = Self.generated(&random)
            let expected = Self.lineTokens(
                HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: textLength))
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
        #expect(lines[0] == [LineToken(range: 0 ..< 2, role: .comment)])
        #expect(lines[1] == [LineToken(range: 0 ..< 2, role: .number)])
        let dropped = LineTokens([tokens[1], tokens[2]], lineRanges: [0 ..< 2, 4 ..< 6])
        #expect(dropped[0].isEmpty)
        #expect(dropped.tokenIndices(ofLine: 1) == 0 ..< 1)
    }

    @Test
    func `tokens move to utf16 offsets across multibyte characters, on the lines that have them`() {
        // "é✓🙂 x" is é (2 bytes, 1 unit), ✓ (3 bytes, 1 unit), 🙂 (4 bytes, 2 units), a space and x; "ab c" is ASCII;
        // "yz 🙂" has its only multibyte character after its last token.
        let text = Array("é✓🙂 x\nab c\nyz 🙂".utf8)
        let lineRanges = [0 ..< 11, 12 ..< 16, 17 ..< 24]
        let tokens = [
            HighlightToken(byteRange: 0 ..< 2, role: .string, modifiers: [.readonly], layer: .lexical, priority: 1),
            HighlightToken(byteRange: 2 ..< 9, role: .comment), HighlightToken(byteRange: 10 ..< 11, role: .keyword),
            HighlightToken(byteRange: 12 ..< 14, role: .number), HighlightToken(byteRange: 15 ..< 16, role: .type),
            HighlightToken(byteRange: 17 ..< 19, role: .string)
        ]
        var lines = LineTokens(tokens, lineRanges: lineRanges)
        let ascii = Array(lines[1])
        let beforeMultibyte = Array(lines[2])
        lines.moveToUTF16(over: text.span, lineRanges: lineRanges)
        #expect(
            lines[0] == [
                LineToken(range: 0 ..< 1, role: .string, modifiers: [.readonly]),
                LineToken(range: 1 ..< 4, role: .comment), LineToken(range: 5 ..< 6, role: .keyword)
            ])
        #expect(Array(lines[1]) == ascii)
        #expect(Array(lines[2]) == beforeMultibyte)
    }

    @Test
    func `utf16 offsets equal the utf16 length of the line before each bound on generated texts`() {
        let characters = ["a", " ", "é", "✓", "変", "🙂", "𝔘", "\n", "\r\n"]
        var random = SeededRNG(seed: 0x16)
        for _ in 0 ..< 500 {
            let text = (0 ..< Int(random.next() % 40)).map { _ in characters[Int(random.next() % 9)] }.joined()
            let bytes = Array(text.utf8)
            // Each line's text, without its `\r` and `\n`, and every character boundary in it, where a scanner cuts.
            var lineRanges: [Range<Int>] = []
            var bounds: [[Int]] = []
            var offset = 0
            for line in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
                let length = line.count - (line.last == UInt8(ascii: "\r") ? 1 : 0)
                lineRanges.append(offset ..< offset + length)
                var lineBounds = [offset]
                for character in String(decoding: line.prefix(length), as: UTF8.self) {
                    lineBounds.append(lineBounds[lineBounds.count - 1] + character.utf8.count)
                }
                bounds.append(lineBounds)
                offset += line.count + 1
            }
            var ranges: [Range<Int>] = []
            for lineBounds in bounds {
                var index = 0
                while index + 1 < lineBounds.count {
                    index += Int(random.next() % 2)
                    let end = min(index + 1 + Int(random.next() % 3), lineBounds.count - 1)
                    guard index < end else { break }
                    ranges.append(lineBounds[index] ..< lineBounds[end])
                    index = end
                }
            }
            var lines = LineTokens(ranges.map { HighlightToken(byteRange: $0, role: .keyword) }, lineRanges: lineRanges)
            lines.moveToUTF16(over: bytes.span, lineRanges: lineRanges)
            for (line, range) in lineRanges.enumerated() {
                let lineBytes = bytes[range]
                let expected = ranges.filter { range.contains($0.lowerBound) }
                    .map {
                        Self.utf16Count(lineBytes[..<$0.lowerBound]) ..< Self.utf16Count(lineBytes[..<$0.upperBound])
                    }
                #expect(lines[line].map(\.range) == expected, "line \(line) of \(text.debugDescription)")
            }
        }
    }

    @Test
    func `a line token takes twelve bytes, and a bound past four gigabytes is clamped`() {
        #expect(MemoryLayout<LineToken>.stride == 12)
        let token = LineToken(range: 3 ..< Int(UInt32.max) + 10, role: .comment, modifiers: [.deprecated])
        #expect(token.range == 3 ..< Int(UInt32.max))
        #expect(token.modifiers == [.deprecated])
    }

    @Test
    func `lines built from their cut tokens, and appended, equal the lines cut from the whole text`() {
        let tokens = [
            HighlightToken(byteRange: 0 ..< 3, role: .keyword), HighlightToken(byteRange: 4 ..< 9, role: .comment),
            HighlightToken(byteRange: 10 ..< 11, role: .number)
        ]
        let lineRanges = [0 ..< 3, 4 ..< 6, 7 ..< 9, 10 ..< 12]
        let whole = LineTokens(tokens, lineRanges: lineRanges)

        var appended = LineTokens(tokens: Array(whole.tokens[0 ..< 2]), offsets: [0, 1, 2])
        appended.append(contentsOf: LineTokens(tokens: Array(whole.tokens[2...]), offsets: [0, 1, 2]))

        #expect(appended == whole)
        #expect(appended.count == 4)
        #expect(appended[3] == [LineToken(range: 0 ..< 1, role: .number)])
    }

    /// `HighlightToken.byLine`'s lines as line tokens, which keep no layer and no priority.
    private static func lineTokens(_ lines: [[HighlightToken]]) -> [[LineToken]] {
        lines.map { line in line.map { LineToken(range: $0.byteRange, role: $0.role, modifiers: $0.modifiers) } }
    }

    private static func utf16Count(_ bytes: ArraySlice<UInt8>) -> Int {
        String(decoding: bytes, as: UTF8.self).utf16.count
    }

    /// Random ascending, disjoint tokens over a random text of short lines, some empty.
    private static func generated(_ random: inout SeededRNG) -> ([HighlightToken], [Int], Int) {
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
