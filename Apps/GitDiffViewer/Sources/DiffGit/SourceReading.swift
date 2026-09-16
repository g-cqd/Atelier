import AemiRuntime
import DiffCore
public import Foundation

/// Everything the model needs to know about a comparison target, behind one seam so tests can substitute it.
public protocol SourceReading: Sendable {
    func repositoryInfo(containing url: URL) async -> RepositoryInfo?
    func entries(of source: ComparisonSource) async throws -> [SourceEntry]
    /// Files git ignores in a working tree, which `entries(of:)` leaves out; empty for every other kind of source.
    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry]
    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String
    /// Contents of many files at once, keyed by relative path; sources that can batch reads override this.
    func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String]
    /// Renames git detects between the two sources, old path to new path, when both are trees of one repository.
    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String]
    /// The commit hash `ref` names in `repository`.
    /// - Throws: When the ref names nothing, or git cannot run.
    func resolve(ref: String, in repository: URL) async throws -> String
}

/// Concurrent file reads for sources without batch reads; bounded so a large folder does not open a file storm.
private let fileReadConcurrency = 6

extension SourceReading {
    public func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        []
    }

    /// A source with no git behind it names every ref by itself.
    public func resolve(ref: String, in repository: URL) async throws -> String {
        ref
    }

    public func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String] {
        let pairs = try await mapConcurrently(entries, limit: fileReadConcurrency) { entry in
            (entry.relativePath, try await content(of: entry, in: source))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}
