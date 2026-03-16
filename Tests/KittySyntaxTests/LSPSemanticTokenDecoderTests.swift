import Testing

@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct LSPSemanticTokenDecoderTests {
    @Test
    func `Decode single token on first line`() {
        let legend = SemanticTokensLegend(
            tokenTypes: ["keyword"],
            tokenModifiers: ["declaration"]
        )
        // deltaLine=0, deltaStartChar=0, length=3, tokenType=0(keyword), modifiers=0
        let data: [UInt32] = [0, 0, 3, 0, 0]
        let source = "let x = 1"

        let tokens = LSPSemanticTokenDecoder.decode(data: data, legend: legend, source: source)
        #expect(tokens.count == 1)
        #expect(tokens[0].byteRange == 0..<3)
        #expect(tokens[0].role == .keyword)
        #expect(tokens[0].layer == .semantic)
    }

    @Test
    func `Decode multiple tokens across lines`() {
        let legend = SemanticTokensLegend(
            tokenTypes: ["keyword", "variable"],
            tokenModifiers: []
        )
        let source = "let x\nvar y"
        // Token 1: line 0, char 0, len 3, type keyword
        // Token 2: delta line 1, char 0, len 3, type keyword
        let data: [UInt32] = [0, 0, 3, 0, 0, 1, 0, 3, 0, 0]

        let tokens = LSPSemanticTokenDecoder.decode(data: data, legend: legend, source: source)
        #expect(tokens.count == 2)
        #expect(tokens[0].byteRange == 0..<3)  // "let"
        #expect(tokens[1].byteRange == 6..<9)  // "var"
    }

    @Test
    func `Decode with modifiers`() {
        let legend = SemanticTokensLegend(
            tokenTypes: ["variable"],
            tokenModifiers: ["declaration", "deprecated"]
        )
        // modifiers = 0b11 = declaration + deprecated
        let data: [UInt32] = [0, 0, 5, 0, 3]
        let source = "hello world"

        let tokens = LSPSemanticTokenDecoder.decode(data: data, legend: legend, source: source)
        #expect(tokens.count == 1)
        #expect(tokens[0].modifiers.contains(.declaration))
        #expect(tokens[0].modifiers.contains(.deprecated))
    }

    @Test
    func `Empty data returns empty tokens`() {
        let legend = SemanticTokensLegend(tokenTypes: [])
        let tokens = LSPSemanticTokenDecoder.decode(data: [], legend: legend, source: "hello")
        #expect(tokens.isEmpty)
    }

    @Test
    func `Semantic tokens merge with structural tokens`() {
        let structuralTokens = [
            HighlightToken(byteRange: 0..<3, role: .variable, layer: .structural),
            HighlightToken(byteRange: 4..<9, role: .string, layer: .structural),
        ]
        let semanticTokens = [
            HighlightToken(byteRange: 0..<3, role: .function, layer: .semantic),
        ]

        let all = structuralTokens + semanticTokens
        let merged = HighlightMerger.merge(all, sourceByteCount: 10)

        // Semantic should override structural for 0..<3
        let firstToken = merged.first(where: { $0.byteRange.lowerBound == 0 })
        #expect(firstToken?.role == .function)

        // Structural should remain for 4..<9
        let secondToken = merged.first(where: { $0.byteRange.lowerBound == 4 })
        #expect(secondToken?.role == .string)
    }

    @Test
    func `No provider produces identical output to structural-only`() {
        let tokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .structural),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 3)
        #expect(merged.count == 1)
        #expect(merged[0].role == .keyword)
    }

    @Test
    func `Lexical baseline ensures fallback languages get tokens in merged path`() {
        // When structural tokens are empty, lexical tokens should still provide
        // styling for known keywords. This tests the three-layer model.
        let lexicalTokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .lexical),
            HighlightToken(byteRange: 4..<9, role: .string, layer: .lexical),
        ]
        let merged = HighlightMerger.merge(lexicalTokens, sourceByteCount: 10)
        #expect(merged.count == 2)
        #expect(merged[0].role == .keyword)
        #expect(merged[1].role == .string)
    }

    @Test
    func `Structural tokens override lexical baseline`() {
        let tokens = [
            HighlightToken(byteRange: 0..<3, role: .keyword, layer: .lexical),
            HighlightToken(byteRange: 0..<3, role: .keywordFunction, layer: .structural),
        ]
        let merged = HighlightMerger.merge(tokens, sourceByteCount: 3)
        #expect(merged.count == 1)
        #expect(merged[0].role == .keywordFunction)
    }
}
