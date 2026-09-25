public import AtelierSyntaxModel

/// Why a tier gave up; the lines keep what the tiers below it found.
public enum TierFailure: Error, Sendable, Equatable {
    /// The tier did not finish within its deadline.
    case deadline(Duration)
    /// The tier's result failed its quality gate, such as too many bytes in unexpected nodes.
    case gate(String)
    /// Anything else, described.
    case failed(String)
}

/// A highlighting tier (PERF-11): one engine that reads a text and emits its tokens, visible lines first. The job
/// (``HighlightTiers``) runs every supported tier of a text at once, each on its own.
public protocol HighlightTier: Sendable {
    var layer: HighlightLayer { get }
    var coverage: TierCoverage { get }
    /// How long the tier may take before the job gives up on it; nil lets it run to the end.
    var deadline: Duration? { get }
    func supports(_ language: Language) -> Bool
    /// Emits the visible lines first, then the rest (``TierRequest/chunks``).
    /// - Throws: `CancellationError` once cancelled, or a ``TierFailure``.
    func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws
}

extension HighlightTier {
    public var deadline: Duration? { nil }
}
