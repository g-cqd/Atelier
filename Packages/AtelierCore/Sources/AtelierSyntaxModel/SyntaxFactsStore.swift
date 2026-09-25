import Synchronization

/// What one parse of each text learned, kept per revision and bounded in bytes, the least recently used going first
/// (PERF-11 step 3, design note section 3.4; PERF-08's third criterion).
///
/// Whoever needs a text's facts first, the colour tier, the intraline diff or the hover index, parses the text and
/// stores them; the others read them. A content key names the same text in every document, so a revision keyed by
/// content is looked up by its language and key alone. A lock rather than an actor guards the entries: the intraline
/// diff asks from synchronous code. Two callers that miss the same revision at the same moment both parse it; the
/// store keeps one result.
public final class SyntaxFactsStore: Sendable {
    /// The byte budget of a store made without one, 48 MB.
    ///
    /// Measured with `SyntaxFactsMemoryBenchmark` over this repository's 525 Swift source files, 3.4 MB of source:
    /// their facts hold 11.9 bytes per byte of source as the allocator reports it, and ``SyntaxFacts/estimatedBytes``,
    /// which the store counts, comes within 4 % of that. A full card list, 200 files with
    /// both sides, at the mean file size of 6.9 KB, holds some 30 MB: the budget keeps a whole list's facts, so hover,
    /// colour and intraline never parse a side of it twice, with room for larger files.
    public static let defaultByteLimit = 48 << 20

    private struct Key: Hashable {
        let language: Language
        let key: SourceRevision.Key
        /// Only a versioned revision's document matters: content is the same text in any document.
        let documentID: String?

        init(_ revision: SourceRevision) {
            language = revision.language
            key = revision.key
            if case .version = revision.key { documentID = revision.documentID } else { documentID = nil }
        }
    }

    private struct State {
        var entries: [Key: (facts: SyntaxFacts, bytes: Int, use: UInt64)] = [:]
        var bytes = 0
        var clock: UInt64 = 0
        var extractions = 0
    }

    /// The most bytes the entries may hold; one entry larger than this is kept alone.
    public let byteLimit: Int
    private let state = Mutex(State())

    public init(byteLimit: Int = SyntaxFactsStore.defaultByteLimit) {
        self.byteLimit = byteLimit
    }

    /// How many times ``facts(for:extract:)`` missed and extracted facts, a parse each.
    public var extractions: Int { state.withLock { $0.extractions } }
    /// The estimated bytes the entries hold.
    public var byteCount: Int { state.withLock { $0.bytes } }
    public var entryCount: Int { state.withLock { $0.entries.count } }

    /// The facts kept for `revision`, marked as used; nil when none are.
    public func facts(for revision: SourceRevision) -> SyntaxFacts? {
        state.withLock { state in
            let key = Key(revision)
            guard var entry = state.entries[key] else { return nil }
            state.clock += 1
            entry.use = state.clock
            state.entries[key] = entry
            return entry.facts
        }
    }

    /// The facts kept for `revision`, or those `extract` finds, which are kept; nil when `extract` gives none, as when
    /// it was cancelled. `extract` runs outside the lock.
    /// - Complexity: O(1) on a hit; `extract`'s cost, plus O(entries) when the store evicts, on a miss.
    public func facts(for revision: SourceRevision, extract: () -> SyntaxFacts?) -> SyntaxFacts? {
        if let facts = facts(for: revision) { return facts }
        state.withLock { $0.extractions += 1 }
        guard let facts = extract() else { return nil }
        insert(facts, for: revision)
        return facts
    }

    /// Keeps `facts` for `revision`, then evicts the least recently used entries until the store is within its limit.
    public func insert(_ facts: SyntaxFacts, for revision: SourceRevision) {
        let bytes = facts.estimatedBytes
        state.withLock { state in
            let key = Key(revision)
            state.clock += 1
            if let replaced = state.entries.updateValue((facts, bytes, state.clock), forKey: key) {
                state.bytes -= replaced.bytes
            }
            state.bytes += bytes
            while state.bytes > byteLimit, state.entries.count > 1,
                let oldest = state.entries.filter({ $0.key != key }).min(by: { $0.value.use < $1.value.use })
            {
                state.bytes -= oldest.value.bytes
                state.entries[oldest.key] = nil
            }
        }
    }
}
