import AemiTestKit
import AtelierSyntaxModel
import Testing

/// The per-line merge of every tier's tokens, and the coverage rule (PERF-11 step 2).
struct LayeredLineTokensTests {
    private static let revision = SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob"))

    /// An update over one line holding `tokens`.
    private static func update(
        _ layer: HighlightLayer, _ coverage: TierCoverage, line: Int = 0, _ tokens: [HighlightToken]
    ) -> TierUpdate {
        TierUpdate(
            layer: layer, coverage: coverage, revision: revision, lines: line ..< line + 1,
            tokens: LineTokens(tokens, lineRanges: [0 ..< 100]))
    }

    @Test
    func `a complete tier hides the layers below it on its lines, even where it leaves a byte plain`() {
        // `let set = [1]`: the lexer calls `set` a keyword, swift-syntax leaves it plain.
        var layered = LayeredLineTokens(lineCount: 2)
        let keyword = HighlightToken(byteRange: 0 ..< 3, role: .keyword, layer: .lexical)
        layered.apply(
            Self.update(.lexical, .complete, [keyword, .init(byteRange: 4 ..< 7, role: .keyword, layer: .lexical)]))
        layered.apply(Self.update(.lexical, .complete, line: 1, [keyword]))

        layered.apply(
            Self.update(.syntactic, .complete, [.init(byteRange: 0 ..< 3, role: .keyword, layer: .syntactic)]))

        #expect(layered.merged(line: 0) == [LineToken(range: 0 ..< 3, role: .keyword)])
        #expect(layered.merged(line: 1) == [LineToken(range: 0 ..< 3, role: .keyword)])
        #expect(layered.layers(onLine: 0) == [.lexical, .syntactic])
    }

    @Test
    func `a sparse tier adds to the complete one below it`() {
        var layered = LayeredLineTokens(lineCount: 1)
        layered.apply(
            Self.update(
                .syntactic, .complete,
                [
                    .init(byteRange: 0 ..< 3, role: .keyword, layer: .syntactic),
                    .init(byteRange: 10 ..< 14, role: .string, layer: .syntactic)
                ]))

        layered.apply(Self.update(.semantic, .sparse, [.init(byteRange: 4 ..< 7, role: .variable, layer: .semantic)]))

        #expect(layered.merged(line: 0)?.map(\.role) == [.keyword, .variable, .string])
    }

    @Test
    func `a line no tier reached has no tokens`() {
        var layered = LayeredLineTokens(lineCount: 3)
        layered.apply(Self.update(.lexical, .complete, line: 1, []))

        #expect(layered.merged(line: 0) == nil)
        #expect(layered.merged(line: 1) == [])
        #expect(layered.merged(line: 5) == nil)
    }

    @Test
    func `the merge equals HighlightMerger's over the layers the coverage rule shows, on generated lines`() {
        var random = SeededRNG(seed: 0x9E)
        let allLayers: [HighlightLayer] = [.lexical, .structural, .syntactic, .semantic]
        for _ in 0 ..< 500 {
            var layered = LayeredLineTokens(lineCount: 1)
            var landed: [(layer: HighlightLayer, coverage: TierCoverage, tokens: [HighlightToken])] = []
            for layer in allLayers where random.next() % 3 != 0 {
                let coverage: TierCoverage = random.next() % 2 == 0 ? .complete : .sparse
                let tokens = Self.generatedTokens(layer: layer, &random)
                landed.append((layer, coverage, tokens))
                layered.apply(Self.update(layer, coverage, tokens))
            }
            guard !landed.isEmpty else {
                #expect(layered.merged(line: 0) == nil)
                continue
            }
            let base = landed.lastIndex { $0.coverage == .complete } ?? 0
            let shown = [landed[base]] + landed[(base + 1)...].filter { $0.coverage == .sparse }
            let all = shown.flatMap(\.tokens)
            let expected = HighlightMerger.merge(all, sourceByteCount: all.map(\.byteRange.upperBound).max() ?? 0)
                .map { LineToken(range: $0.byteRange, role: $0.role, modifiers: $0.modifiers) }

            #expect(layered.merged(line: 0) == expected, "\(landed)")
        }
    }

    @Test
    func `overlapping tokens of one layer come out disjoint, the earlier keeping the bytes they share`() {
        var layered = LayeredLineTokens(lineCount: 1)
        layered.apply(
            Self.update(
                .lexical, .complete,
                [
                    HighlightToken(byteRange: 0 ..< 6, role: .string),
                    HighlightToken(byteRange: 4 ..< 9, role: .comment),
                    HighlightToken(byteRange: 9 ..< 9, role: .number)
                ]))

        #expect(
            layered.merged(line: 0) == [
                LineToken(range: 0 ..< 6, role: .string), LineToken(range: 6 ..< 9, role: .comment)
            ])
    }

    /// Ascending, disjoint tokens of `layer` somewhere in the first 60 bytes of a line.
    private static func generatedTokens(layer: HighlightLayer, _ random: inout SeededRNG) -> [HighlightToken] {
        var tokens: [HighlightToken] = []
        var cursor = Int(random.next() % 4)
        while cursor < 60 {
            let length = Int(random.next() % 8) + 1
            let role = HighlightRole.allCases[Int(random.next() % UInt64(HighlightRole.allCases.count))]
            tokens.append(
                HighlightToken(
                    byteRange: cursor ..< cursor + length, role: role,
                    modifiers: HighlightModifierSet(rawValue: UInt16(random.next() % 4)), layer: layer))
            cursor += length + Int(random.next() % 6)
        }
        return tokens
    }
}
