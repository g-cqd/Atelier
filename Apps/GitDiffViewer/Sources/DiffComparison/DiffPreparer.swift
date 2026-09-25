package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
import Foundation
import Observation

import func AemiRuntime.mapConcurrently

/// Reads and diffs files, keeping every result by content so a file compared once shows at once afterwards.
/// Blob ids are content hashes on every kind of source, so cached entries never go stale; the cache is only bounded.
@MainActor
package final class DiffPreparer {
    package static let cacheLimit = 512
    package static let prefetchBatch = 16

    private let reader: any SourceReading
    private let taskProvider: any TaskProvider
    /// Where a side's syntax facts are kept, shared with the colour tier and hover (PERF-11 step 3).
    private let store: SyntaxFactsStore?
    private var cache: [Key: PreparedDiff] = [:]
    private var prefetchTask: Task<Void, Never>?

    package init(reader: any SourceReading, taskProvider: any TaskProvider, store: SyntaxFactsStore? = nil) {
        self.reader = reader
        self.taskProvider = taskProvider
        self.store = store
    }

    private struct Key: Hashable {
        let path: String
        let oldBlob: String
        let newBlob: String
        let granularity: IntralineGranularity
        let heuristics: DiffHeuristics

        init?(_ pair: FilePair, granularity: IntralineGranularity, heuristics: DiffHeuristics) {
            guard pair.old == nil || pair.old?.blobID != nil, pair.new == nil || pair.new?.blobID != nil else {
                return nil
            }
            path = pair.path
            oldBlob = pair.old?.blobID ?? ""
            newBlob = pair.new?.blobID ?? ""
            self.granularity = granularity
            self.heuristics = heuristics
        }
    }

    package func cached(_ pair: FilePair, granularity: IntralineGranularity, heuristics: DiffHeuristics)
        -> PreparedDiff?
    {
        Key(pair, granularity: granularity, heuristics: heuristics).flatMap { cache[$0] }
    }

    /// Diffs for `pairs` in order: cached ones as they are, the rest read in one batch per side and diffed in
    /// parallel off the main actor, then cached. Structured, so cancelling the caller stops the work and the
    /// caller's priority is the work's priority.
    package func prepare(
        _ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity,
        heuristics: DiffHeuristics
    ) async throws -> [PreparedDiff] {
        guard !pairs.isEmpty else { return [] }
        try Task.checkCancellation()
        var result: [PreparedDiff?] = pairs.map { cached($0, granularity: granularity, heuristics: heuristics) }
        let misses = pairs.indices.filter { result[$0] == nil }
        guard !misses.isEmpty else { return result.compactMap { $0 } }

        let store = store
        let prepared = try await Self.load(misses.map { pairs[$0] }, left: left, right: right, reader: reader) {
            PreparedDiff($0, granularity: granularity, heuristics: heuristics, store: store)
        }
        try Task.checkCancellation()
        if cache.count + prepared.count > Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        for (index, diff) in zip(misses, prepared) {
            result[index] = diff
            if let key = Key(pairs[index], granularity: granularity, heuristics: heuristics) { cache[key] = diff }
        }
        return result.compactMap { $0 }
    }

    /// Prepares `pairs` in the background at low priority; a new prefetch or a cancel supersedes it.
    package func prefetch(
        _ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity,
        heuristics: DiffHeuristics
    ) {
        prefetchTask?.cancel()
        let pending = pairs.filter { cached($0, granularity: granularity, heuristics: heuristics) == nil }
        guard !pending.isEmpty else { return }
        prefetchTask = taskProvider.task(priority: .utility) {
            for start in stride(from: 0, to: pending.count, by: Self.prefetchBatch) {
                guard !Task.isCancelled else { return }
                _ = try? await prepare(
                    Array(pending[start ..< min(start + Self.prefetchBatch, pending.count)]), left: left, right: right,
                    granularity: granularity, heuristics: heuristics)
            }
        }
    }

    package func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    /// Reads `pairs`' sides and prepares each file with `prepare`, the files side by side.
    @concurrent
    private static func load(
        _ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, reader: any SourceReading,
        prepare: @escaping @Sendable (FileDiffInput) -> PreparedDiff
    ) async throws -> [PreparedDiff] {
        async let oldTexts = reader.contents(of: pairs.compactMap(\.old), in: left)
        async let newTexts = reader.contents(of: pairs.compactMap(\.new), in: right)
        let (olds, news) = try await (oldTexts, newTexts)
        let inputs = pairs.map { pair in
            let language = Language(fileExtension: URL(filePath: pair.path).pathExtension)
            func revision(_ entry: SourceEntry?) -> SourceRevision? {
                entry?.blobID.map { SourceRevision(documentID: pair.path, language: language, key: .content($0)) }
            }
            return FileDiffInput(
                title: pair.path,
                oldText: pair.old.flatMap { olds[$0.relativePath] } ?? "",
                newText: pair.new.flatMap { news[$0.relativePath] } ?? "",
                language: language, oldRevision: revision(pair.old), newRevision: revision(pair.new)
            )
        }
        return try await mapConcurrently(inputs, limit: ProcessInfo.processInfo.activeProcessorCount, prepare)
    }
}
