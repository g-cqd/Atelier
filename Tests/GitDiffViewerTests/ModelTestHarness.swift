import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// The model under test with its doubles: an in-memory source reader, a task provider spy the tests settle on,
/// and a hand-advanced clock. Shared by every model suite.
@MainActor
struct ModelTestHarness {
    let taskProvider = TaskProviderSpy()
    let reader = FakeSourceReader()
    let uptime = FakeUptime()
    static let leftURL = URL(filePath: "/left", directoryHint: .isDirectory)
    static let rightURL = URL(filePath: "/right", directoryHint: .isDirectory)

    func makeSUT() -> DiffViewerModel {
        let suite = "GitDiffViewerTests.model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return DiffViewerModel(
            settings: ViewerSettings(defaults: defaults), reader: reader, taskProvider: taskProvider,
            uptime: uptime.provider)
    }

    func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    /// Loads both folders; the model recomputes the comparison itself once both sides land.
    func load(_ sut: DiffViewerModel) async throws {
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
    }
}

/// A monotonic time the test advances by hand, read by the model as nanoseconds.
final class FakeUptime: Sendable {
    private let nanoseconds = Mutex<Int64>(0)

    var now: Duration {
        get { .nanoseconds(nanoseconds.withLock { $0 }) }
        set {
            let components = newValue.components
            nanoseconds.withLock { $0 = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000 }
        }
    }

    /// The provider shape the model takes.
    var provider: @Sendable () -> Int64 {
        { [self] in nanoseconds.withLock { $0 } }
    }
}

/// In-memory source reader; records the paths whose content was requested and can hold a read until released.
final class FakeSourceReader: SourceReading, Sendable {
    private struct State {
        var entries: [ComparisonSource: [SourceEntry]] = [:]
        var ignored: [ComparisonSource: [SourceEntry]] = [:]
        var repositories: [URL: RepositoryInfo] = [:]
        var contents: [String: String] = [:]
        var gate: [String: AsyncProbe<Void>] = [:]
        var gitRenames: [String: String] = [:]
    }

    private let state = Mutex(State())
    let contentRequests = AsyncProbe<String>()

    var entries: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.entries } }
        set { state.withLock { $0.entries = newValue } }
    }

    var contents: [String: String] {
        get { state.withLock { $0.contents } }
        set { state.withLock { $0.contents = newValue } }
    }

    var ignored: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.ignored } }
        set { state.withLock { $0.ignored = newValue } }
    }

    var repositories: [URL: RepositoryInfo] {
        get { state.withLock { $0.repositories } }
        set { state.withLock { $0.repositories = newValue } }
    }

    /// Reads of a path, or entries of a directory path, wait for one element per read on their gate.
    var gate: [String: AsyncProbe<Void>] {
        get { state.withLock { $0.gate } }
        set { state.withLock { $0.gate = newValue } }
    }

    var gitRenames: [String: String] {
        get { state.withLock { $0.gitRenames } }
        set { state.withLock { $0.gitRenames = newValue } }
    }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? { repositories[url] }

    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] { gitRenames }

    func entries(of source: ComparisonSource) async throws -> [SourceEntry] {
        if case .directory(let url) = source, let gate = gate[url.path(percentEncoded: false)] {
            _ = try await gate.next()
        }
        return entries[source] ?? []
    }

    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        ignored[source] ?? []
    }

    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        contentRequests.send(entry.relativePath)
        if let gate = gate[entry.relativePath] {
            _ = try await gate.next()
        }
        return contents[entry.relativePath] ?? "\(entry.relativePath) \(entry.blobID ?? "")\n"
    }
}
