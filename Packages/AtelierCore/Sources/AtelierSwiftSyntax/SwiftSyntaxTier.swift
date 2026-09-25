public import AtelierHighlighting
public import AtelierSyntaxModel

/// swift-syntax as a tier of the tier job (PERF-11): Swift's structural tier (D33), complete over the lines it
/// covers. It parses the whole text once, then classifies the visible lines first and the rest after them, each step
/// on ``SwiftSyntaxStack``. A text past the unexpected-bytes gate fails, and its lines keep the tiers below.
///
/// Given a ``SyntaxFactsStore``, a text whose revision is keyed by content takes its tokens from the facts one parse
/// found for it, which the intraline diff and hover read too, and a text it parses leaves them there (step 3).
public struct SwiftSyntaxTier: AtelierHighlighting.HighlightTier {
    /// How long a side may take, parse and classification together (design note, section 4.7).
    public static let defaultDeadline: Duration = .milliseconds(200)

    public let deadline: Duration?
    private let store: SyntaxFactsStore?

    /// - Parameters:
    ///   - deadline: How long a side may take before the job gives up on it.
    ///   - store: Where the facts of the texts it reads are kept; nil parses every text for its colour alone.
    public init(deadline: Duration? = SwiftSyntaxTier.defaultDeadline, store: SyntaxFactsStore? = nil) {
        self.deadline = deadline
        self.store = store
    }

    public var layer: HighlightLayer { .syntactic }
    public var coverage: TierCoverage { .complete }

    public func supports(_ language: Language) -> Bool {
        language == .swift
    }

    /// - Throws: `CancellationError` once cancelled, between the parse and a chunk's classification or within it;
    ///   ``TierFailure/gate(_:)`` when the text does not read as Swift.
    /// - Complexity: one parse, then O(nodes) over the chunks.
    public func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        if let store, case .content = request.revision.key {
            return try await run(request, store: store, emit: emit)
        }
        let flag = CancellationFlag()
        try await withTaskCancellationHandler {
            let text = request.text
            let parsed = try Self.unwrap(
                await SwiftSyntaxStack.run {
                    Result { () throws(SwiftSyntaxHighlights.Failure) in
                        try SwiftSyntaxHighlights.Parsed(text, isCancelled: flag.isSet)
                    }
                })
            for chunk in request.chunks {
                let first = request.lineRanges[chunk.lowerBound].lowerBound
                let bytes = first ..< request.lineRanges[chunk.upperBound - 1].upperBound
                let tokens = try Self.unwrap(
                    await SwiftSyntaxStack.run {
                        Result { () throws(SwiftSyntaxHighlights.Failure) in
                            try parsed.tokens(in: bytes, isCancelled: flag.isSet)
                        }
                    })
                await emit(
                    TierUpdate(
                        layer: layer, coverage: coverage, revision: request.revision, lines: chunk,
                        tokens: request.lineTokens(tokens, lines: chunk)))
            }
        } onCancel: {
            flag.set()
        }
    }

    /// The facts path: the whole text's tokens from one parse shared with the intraline diff and hover, cut into the
    /// same chunks, visible lines first.
    private func run(_ request: TierRequest, store: SyntaxFactsStore, emit: (TierUpdate) async -> Void) async throws {
        let flag = CancellationFlag()
        let facts = await withTaskCancellationHandler {
            await SwiftSyntaxFacts.facts(
                for: request.revision, text: request.text, in: store, isCancelled: { flag.isSet() })
        } onCancel: {
            flag.set()
        }
        try Task.checkCancellation()
        guard let facts else { throw CancellationError() }
        guard let highlights = facts.highlights else {
            throw TierFailure.gate(
                "\(Int((facts.unexpectedShare * 100).rounded())) % of the bytes lie in unexpected nodes")
        }
        for chunk in request.chunks {
            try Task.checkCancellation()
            await emit(
                TierUpdate(
                    layer: layer, coverage: coverage, revision: request.revision, lines: chunk,
                    tokens: request.lineTokens(highlights, lines: chunk)))
        }
    }

    private static func unwrap<Value>(_ result: Result<Value, SwiftSyntaxHighlights.Failure>) throws -> Value {
        switch result {
            case .success(let value): return value
            case .failure(.cancelled): throw CancellationError()
            case .failure(.tooManyUnexpectedBytes(let share)):
                throw TierFailure.gate("\(Int((share * 100).rounded())) % of the bytes lie in unexpected nodes")
        }
    }
}
