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

        #expect(layered.merged(line: 0)?.map(\.byteRange) == [0 ..< 3])
        #expect(layered.merged(line: 0)?.map(\.layer) == [.syntactic])
        #expect(layered.merged(line: 1) == [keyword])
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
    func `a lexical-only merge equals HighlightMerger's`() {
        // Overlapping tokens of one layer, as a grammar's query makes them: the narrower wins.
        let tokens = [
            HighlightToken(byteRange: 0 ..< 20, role: .string, layer: .lexical),
            HighlightToken(byteRange: 5 ..< 7, role: .escape, layer: .lexical),
            HighlightToken(byteRange: 25 ..< 30, role: .comment, layer: .lexical, priority: 1),
            HighlightToken(byteRange: 25 ..< 30, role: .keyword, layer: .lexical, priority: 0)
        ]
        var layered = LayeredLineTokens(lineCount: 1)
        layered.apply(Self.update(.lexical, .complete, tokens))

        #expect(layered.merged(line: 0) == HighlightMerger.merge(tokens, sourceByteCount: 30))
    }
}
