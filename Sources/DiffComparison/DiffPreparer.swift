import func AemiRuntime.mapConcurrently
package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
import Foundation
import Observation

/// Reads and diffs files, keeping every result by content so a file compared once shows at once afterwards.
/// Blob ids are content hashes on every kind of source, so cached entries never go stale; the cache is only bounded.
@MainActor
package final class DiffPreparer {
    package static let cacheLimit = 512
    package static let prefetchBatch = 16

    private let reader: any SourceReading
    private let taskProvider: any TaskProvider
    private var cache: [Key: PreparedDiff] = [:]
    private var prefetchTask: Task<Void, Never>?

    package init(reader: any SourceReading, taskProvider: any TaskProvider) {
        self.reader = reader
        self.taskProvider = taskProvider
    }

    private struct Key: Hashable {
        let path: String
        let oldBlob: String
        let newBlob: String
        let granularity: IntralineGranularity
        let heuristics: DiffHeuristics

        init?(_ pair: FilePair, granularity: IntralineGranularity, heuristics: DiffHeuristics) {
            guard pair.old == nil || pair.old?.blobID != nil, pair.new == nil || pair.new?.blobID != nil else { return nil }
            path = pair.path
            oldBlob = pair.old?.blobID ?? ""
            newBlob = pair.new?.blobID ?? ""
            self.granularity = granularity
            self.heuristics = heuristics
        }
    }

    package func cached(_ pair: FilePair, granularity: IntralineGranularity, heuristics: DiffHeuristics) -> PreparedDiff? {
        Key(pair, granularity: granularity, heuristics: heuristics).flatMap { cache[$0] }
    }

    /// Diffs for `pairs` in order: cached ones as they are, the rest read in one batch per side and diffed in
    /// parallel off the main actor, then cached. Structured, so cancelling the caller stops the work and the
    /// caller's priority is the work's priority.
    package func prepare(
        _ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity, heuristics: DiffHeuristics
    ) async throws -> [PreparedDiff] {
        guard !pairs.isEmpty else { return [] }
        try Task.checkCancellation()
        var result: [PreparedDiff?] = pairs.map { cached($0, granularity: granularity, heuristics: heuristics) }
        let misses = pairs.indices.filter { result[$0] == nil }
        guard !misses.isEmpty else { return result.compactMap { $0 } }

        let prepared = try await Self.load(misses.map { pairs[$0] }, left: left, right: right, granularity: granularity, heuristics: heuristics, reader: reader)
        try Task.checkCancellation()
        if cache.count + prepared.count > Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        for (index, diff) in zip(misses, prepared) {
            result[index] = diff
            if let key = Key(pairs[index], granularity: granularity, heuristics: heuristics) { cache[key] = diff }
        }
        return result.compactMap { $0 }
    }

    /// Prepares `pairs` in the background at low priority; a new prefetch or a cancel supersedes it.
    package func prefetch(_ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity, heuristics: DiffHeuristics) {
        prefetchTask?.cancel()
        let pending = pairs.filter { cached($0, granularity: granularity, heuristics: heuristics) == nil }
        guard !pending.isEmpty else { return }
        prefetchTask = taskProvider.task(priority: .utility) {
            for start in stride(from: 0, to: pending.count, by: Self.prefetchBatch) {
                guard !Task.isCancelled else { return }
                _ = try? await prepare(Array(pending[start..<min(start + Self.prefetchBatch, pending.count)]), left: left, right: right, granularity: granularity, heuristics: heuristics)
            }
        }
    }

    package func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    @concurrent
    private static func load(
        _ pairs: [FilePair], left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity, heuristics: DiffHeuristics, reader: any SourceReading
    ) async throws -> [PreparedDiff] {
        async let oldTexts = reader.contents(of: pairs.compactMap(\.old), in: left)
        async let newTexts = reader.contents(of: pairs.compactMap(\.new), in: right)
        let (olds, news) = try await (oldTexts, newTexts)
        let inputs = pairs.map { pair in
            FileDiffInput(
                title: pair.path,
                oldText: pair.old.flatMap { olds[$0.relativePath] } ?? "",
                newText: pair.new.flatMap { news[$0.relativePath] } ?? "",
                language: Language(fileExtension: URL(filePath: pair.path).pathExtension)
            )
        }
        return try await mapConcurrently(inputs, limit: ProcessInfo.processInfo.activeProcessorCount) {
            PreparedDiff($0, granularity: granularity, heuristics: heuristics)
        }
    }
}
