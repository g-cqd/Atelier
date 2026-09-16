import DiffConcurrency
import DiffCore
import DiffIO
import Foundation

/// Everything the model needs to know about a comparison target, behind one seam so tests can substitute it.
package protocol SourceReading: Sendable {
    func repositoryInfo(containing url: URL) async -> RepositoryInfo?
    func entries(of source: ComparisonSource) async throws -> [SourceEntry]
    /// Files git ignores in a working tree, which `entries(of:)` leaves out; empty for every other kind of source.
    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry]
    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String
    /// Contents of many files at once, keyed by relative path; sources that can batch reads override this.
    func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String]
    /// Renames git detects between the two sources, old path to new path, when both are trees of one repository.
    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String]
}

/// Concurrent file reads for sources without batch reads; bounded so a large folder does not open a file storm.
private let fileReadConcurrency = 6

package extension SourceReading {
    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        []
    }

    func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String] {
        let pairs = try await mapConcurrently(entries, limit: fileReadConcurrency) { entry in (entry.relativePath, try await content(of: entry, in: source)) }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
