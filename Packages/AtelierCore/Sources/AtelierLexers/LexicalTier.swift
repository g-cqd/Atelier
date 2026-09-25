public import AtelierHighlighting
public import AtelierSyntaxModel

/// The scanners as tier 0 of the tier job (PERF-11): the lexer scans the whole text, which costs well under a
/// millisecond, then emits the visible lines first and the rest after them. Its tokens are the baseline every line
/// shows until a complete tier above it lands.
public struct LexicalTier: AtelierHighlighting.HighlightTier {
    public init() {}

    public var layer: HighlightLayer { .lexical }
    public var coverage: TierCoverage { .complete }

    public func supports(_ language: Language) -> Bool {
        LexicalHighlightEngine().supports(language)
    }

    /// - Complexity: O(bytes + tokens) for the scan, then O(tokens + bytes) per chunk emitted.
    public func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        let tokens = Self.scan(request.text, language: request.revision.language)
        for chunk in request.chunks {
            try Task.checkCancellation()
            await emit(
                TierUpdate(
                    layer: layer, coverage: coverage, revision: request.revision, lines: chunk,
                    tokens: request.lineTokens(tokens, lines: chunk)))
        }
    }

    private static func scan(_ text: String, language: Language) -> [HighlightToken] {
        let utf8 = text.utf8Span
        return LexicalHighlightEngine().highlight(utf8: utf8.span, language: language)
    }
}
