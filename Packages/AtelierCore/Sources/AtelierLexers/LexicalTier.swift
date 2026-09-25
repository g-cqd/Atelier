public import AtelierHighlighting
public import AtelierSyntaxModel

/// The scanners as tier 0 of the tier job (PERF-11), through ``ProgressiveHighlighting``: the visible lines are lexed
/// and emitted first, then the lines below them and those above, a line at a time from each line's entry state. Its
/// tokens are the baseline every line shows until a complete tier above it lands.
public struct LexicalTier: AtelierHighlighting.HighlightTier {
    public init() {}

    public var layer: HighlightLayer { .lexical }
    public var coverage: TierCoverage { .complete }

    public func supports(_ language: Language) -> Bool {
        LexicalHighlightEngine().supports(language)
    }

    /// - Complexity: O(bytes + tokens), plus the visible lines' once more when they start inside a construct that an
    ///   earlier line opened.
    public func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        _ = await ProgressiveHighlighting.run(
            request, lexer: LexicalLineLexer(language: request.revision.language), emit: emit)
        try Task.checkCancellation()
    }
}
