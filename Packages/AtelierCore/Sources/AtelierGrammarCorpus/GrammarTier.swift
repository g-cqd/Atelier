public import AtelierHighlighting
import AtelierParser
public import AtelierSyntaxModel
import Synchronization

/// A tree-sitter grammar as a tier of the tier job (PERF-11 step 4): the structural layer, complete over the lines it
/// covers once its parse passes the quality gate.
///
/// A run waits for its language's tables, which ``SyntaxArtifactsCache`` loads one grammar at a time, then parses the
/// whole text against its own deadline, measured on the tier's clock from the parse's start, so a slow table load
/// never counts against a parse. It queries the tree for the visible lines first, then the rest. What each grammar
/// did is kept in a ``GrammarTierRecord``, which decides before any parse whether one starts at all:
/// - a text whose content already failed with this grammar is not parsed again;
/// - a text the grammar's last observed throughput predicts past the deadline is not parsed; the first text of a
///   grammar always is;
/// - a grammar that failed three texts in a row, by its deadline, its gate or its parser, parses nothing more until
///   its grammar key, and so its hash, changes.
///
/// The lines of a text the tier gives up on keep the tiers below it.
public struct GrammarTier: AtelierHighlighting.HighlightTier {
    /// How long a parse may take (design note, section 4.7; review §7.4).
    public static let defaultDeadline: Duration = .milliseconds(250)

    /// Parses a text with an engine; the tier's seam for tests.
    typealias Parse = @Sendable (GrammarEngine, String) async throws -> SyntaxTree

    private let artifacts: SyntaxArtifactsCache
    private let record: GrammarTierRecord
    private let parseDeadline: Duration
    private let clock: any Clock<Duration>
    private let parse: Parse

    /// - Parameters:
    ///   - artifacts: Where each language's tables and query load from, one grammar at a time.
    ///   - record: What each grammar did, shared by every tier of an app that highlights with the same grammars.
    ///   - deadline: How long a parse may take.
    ///   - clock: The clock the deadline is measured on.
    public init(
        artifacts: SyntaxArtifactsCache, record: GrammarTierRecord = GrammarTierRecord(),
        deadline: Duration = GrammarTier.defaultDeadline, clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.init(artifacts: artifacts, record: record, deadline: deadline, clock: clock) { engine, text in
            try engine.parse(text, externalScanner: engine.makeScanner())
        }
    }

    init(
        artifacts: SyntaxArtifactsCache, record: GrammarTierRecord, deadline: Duration, clock: any Clock<Duration>,
        parse: @escaping Parse
    ) {
        self.artifacts = artifacts
        self.record = record
        parseDeadline = deadline
        self.clock = clock
        self.parse = parse
    }

    public var layer: HighlightLayer { .structural }
    public var coverage: TierCoverage { .complete }
    /// None for the job: the tier times its parse itself, from the moment its tables are loaded.
    public var deadline: Duration? { nil }

    public func supports(_ language: Language) -> Bool {
        GrammarEngine.grammarName(of: language) != nil
    }

    /// - Throws: `CancellationError` once cancelled; a ``TierFailure``: `.deadline` when the parse passes its
    ///   deadline, `.gate` when the parse fails the quality gate, `.failed` when the grammar does not load, the text
    ///   is too large, the parser throws, or the record declines the parse.
    public func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        guard let name = GrammarEngine.grammarName(of: request.revision.language) else {
            throw TierFailure.failed("no grammar for \(request.revision.language.name)")
        }
        await artifacts.loadIfNeeded(for: name)
        try Task.checkCancellation()
        guard let loaded = artifacts.artifacts(for: name), let engine = GrammarEngine(loaded) else {
            throw TierFailure.failed("the \(name) grammar does not load")
        }
        let bytes = request.text.utf8.count
        guard bytes <= GrammarEngine.maxSourceBytes else {
            throw TierFailure.failed("\(bytes) bytes are past the grammar's \(GrammarEngine.maxSourceBytes)")
        }
        let content = GrammarTierRecord.ContentKey(request)
        let declined = record.admit(grammar: engine.grammarKey, content: content, bytes: bytes, budget: parseDeadline)
        if let declined { throw declined }
        let tree = try await parseWithinDeadline(request.text, engine: engine, content: content, bytes: bytes)
        for chunk in request.chunks {
            try Task.checkCancellation()
            let bytes =
                request.lineRanges[chunk.lowerBound].lowerBound
                ..< request.lineRanges[chunk.upperBound - 1]
                .upperBound
            let tokens = HighlightMerger.merge(
                engine.tokens(in: tree, byteRange: bytes, layer: layer), sourceByteCount: bytes.upperBound)
            await emit(
                TierUpdate(
                    layer: layer, coverage: coverage, revision: request.revision, lines: chunk,
                    tokens: request.lineTokens(tokens, lines: chunk)))
        }
    }

    /// What racing a parse against its deadline gave.
    private enum Outcome: Sendable {
        case parsed(SyntaxTree, Duration)
        case threw(String)
        case deadline
    }

    /// `text`'s tree, parsed while its deadline runs, and recorded: its throughput, and its failure with the grammar
    /// and the content when it passes the deadline, throws or fails the gate.
    private func parseWithinDeadline(
        _ text: String, engine: GrammarEngine, content: GrammarTierRecord.ContentKey, bytes: Int
    ) async throws -> SyntaxTree {
        let (parse, clock, deadline) = (parse, clock, parseDeadline)
        let outcome = await withTaskGroup(of: Outcome?.self) { group -> Outcome? in
            group.addTask {
                let started = ContinuousClock.now
                do {
                    let tree = try await parse(engine, text)
                    return .parsed(tree, started.duration(to: .now))
                } catch ParseError.cancelled {
                    return nil
                } catch is CancellationError {
                    return nil
                } catch {
                    return .threw(String(describing: error))
                }
            }
            group.addTask {
                do {
                    try await clock.sleep(for: deadline)
                } catch {
                    return nil
                }
                return .deadline
            }
            // The first child with an outcome ends the other: a parse that ends stops the deadline, and a deadline
            // that passes cancels the parse, which stops at its next check.
            for await outcome in group {
                guard let outcome else { continue }
                group.cancelAll()
                return outcome
            }
            return nil
        }
        let grammar = engine.grammarKey
        switch outcome {
            case nil:
                throw CancellationError()
            case .deadline:
                let failure = TierFailure.deadline(deadline)
                record.fail(grammar: grammar, content: content, failure, bytes: bytes, took: .atLeast(deadline))
                throw failure
            case .threw(let description):
                let failure = TierFailure.failed("the parse threw \(description)")
                record.fail(grammar: grammar, content: content, failure, bytes: bytes, took: nil)
                throw failure
            case .parsed(let tree, let elapsed):
                guard GrammarEngine.passesQualityGate(tree) else {
                    let failure = TierFailure.gate(
                        "\(GrammarEngine.errorBytePercent(of: tree)) % of the bytes lie under ERROR nodes")
                    record.fail(grammar: grammar, content: content, failure, bytes: bytes, took: .exactly(elapsed))
                    throw failure
                }
                record.succeed(grammar: grammar, bytes: bytes, elapsed: elapsed)
                return tree
        }
    }
}

/// What each grammar did with the texts ``GrammarTier`` gave it, which decides whether the next parse starts: the
/// failures, by grammar and content; each grammar's last observed throughput; and its failures in a row, which stop
/// it at ``breakerThreshold``.
///
/// Keyed by ``GrammarEngine/grammarKey``, which holds the grammar file's hash, so an edited grammar starts afresh.
public final class GrammarTierRecord: Sendable {
    /// How many texts in a row a grammar may fail before it parses nothing more.
    public static let breakerThreshold = 3
    /// How many failures by content are kept; the oldest go first.
    public static let failureCapacity = 1024

    /// What a text's failure is kept under, besides its grammar: its content key, or for a text that has none, such as
    /// an editor's version, a hash of its bytes and their count.
    public enum ContentKey: Hashable, Sendable {
        case content(String)
        case text(hash: Int, bytes: Int)

        init(_ request: TierRequest) {
            switch request.revision.key {
                case .content(let key): self = .content(key)
                case .version: self = .text(hash: request.text.hashValue, bytes: request.text.utf8.count)
            }
        }
    }

    private struct FailureKey: Hashable {
        let grammar: String
        let content: ContentKey
    }

    private struct GrammarState {
        /// The last parse's time per byte; nil before any parse.
        var nanosecondsPerByte: Double?
        var failuresInARow = 0
    }

    private struct State {
        var failures: [FailureKey: TierFailure] = [:]
        var failureOrder: [FailureKey] = []
        var grammars: [String: GrammarState] = [:]
        var parsesStarted = 0
    }

    private let state = Mutex(State())

    public init() {}

    /// How many parses the record let start, for traces and tests.
    public var parsesStarted: Int {
        state.withLock { $0.parsesStarted }
    }

    /// Whether `grammar` stopped after ``breakerThreshold`` failures in a row.
    public func isStopped(grammar: String) -> Bool {
        state.withLock { ($0.grammars[grammar]?.failuresInARow ?? 0) >= Self.breakerThreshold }
    }

    /// The time `grammar`'s last observed throughput predicts for `bytes`; nil before its first parse.
    public func predictedDuration(grammar: String, bytes: Int) -> Duration? {
        state.withLock { state in
            state.grammars[grammar]?.nanosecondsPerByte.map { .nanoseconds(Int64(($0 * Double(bytes)).rounded(.up))) }
        }
    }

    /// Sets `grammar`'s throughput as though its last parse had taken `elapsed` over `bytes`.
    public func observe(grammar: String, bytes: Int, elapsed: Duration) {
        state.withLock {
            $0.grammars[grammar, default: GrammarState()].nanosecondsPerByte = Self.perByte(elapsed, bytes: bytes)
        }
    }

    /// Nil when a parse of `content`, `bytes` long, may start with `grammar` within `budget`, counting it as started;
    /// otherwise why it may not: the grammar stopped, the content failed before, or the prediction passes the budget.
    func admit(grammar: String, content: ContentKey, bytes: Int, budget: Duration) -> TierFailure? {
        state.withLock { state in
            let grammarState = state.grammars[grammar] ?? GrammarState()
            if grammarState.failuresInARow >= Self.breakerThreshold {
                return .failed("the grammar stopped after \(Self.breakerThreshold) failures in a row")
            }
            if let failure = state.failures[FailureKey(grammar: grammar, content: content)] {
                return failure
            }
            if let perByte = grammarState.nanosecondsPerByte {
                let predicted = Duration.nanoseconds(Int64((perByte * Double(bytes)).rounded(.up)))
                if predicted > budget { return .failed("the parse is predicted to take \(predicted), past \(budget)") }
            }
            state.parsesStarted += 1
            return nil
        }
    }

    /// Records a parse that passed the gate: its throughput, and the end of the grammar's failures in a row.
    func succeed(grammar: String, bytes: Int, elapsed: Duration) {
        state.withLock { state in
            state.grammars[grammar, default: GrammarState()].nanosecondsPerByte = Self.perByte(elapsed, bytes: bytes)
            state.grammars[grammar]?.failuresInARow = 0
        }
    }

    /// How long a failed parse ran over its bytes.
    enum ParseTime {
        /// It ran to its end in this time.
        case exactly(Duration)
        /// It was stopped after this time, at its deadline.
        case atLeast(Duration)
    }

    /// Records `failure` of `content` with `grammar`, one more in the grammar's row, and the throughput the parse
    /// showed over `bytes`: the one it had when it ran to its end, and at least the one its deadline shows when it was
    /// stopped. A parse that threw shows none.
    func fail(grammar: String, content: ContentKey, _ failure: TierFailure, bytes: Int, took time: ParseTime?) {
        state.withLock { state in
            var grammarState = state.grammars[grammar] ?? GrammarState()
            grammarState.failuresInARow += 1
            switch time {
                case .exactly(let elapsed):
                    grammarState.nanosecondsPerByte = Self.perByte(elapsed, bytes: bytes)
                case .atLeast(let elapsed):
                    grammarState.nanosecondsPerByte = max(
                        grammarState.nanosecondsPerByte ?? 0, Self.perByte(elapsed, bytes: bytes))
                case nil:
                    break
            }
            state.grammars[grammar] = grammarState
            let key = FailureKey(grammar: grammar, content: content)
            if state.failures.updateValue(failure, forKey: key) == nil { state.failureOrder.append(key) }
            if state.failureOrder.count > Self.failureCapacity {
                let evicted = state.failureOrder.removeFirst()
                state.failures[evicted] = nil
            }
        }
    }

    private static func perByte(_ elapsed: Duration, bytes: Int) -> Double {
        let components = elapsed.components
        let nanoseconds = Double(components.seconds) * 1e9 + Double(components.attoseconds) / 1e9
        return nanoseconds / Double(max(bytes, 1))
    }
}
