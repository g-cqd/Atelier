import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The model's freshness wiring over a scripted repository: a save made while a reload runs is not lost (GIT-01,
/// GDV B4). A synthetic watcher and a virtual clock drive the watcher; the time limit bounds a reload that never
/// comes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiffViewerModelFreshnessTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
    private nonisolated static let tree = ComparisonSource.directory(root)
    private static let treeDebounce: Duration = .milliseconds(600)
    private static let refDebounce: Duration = .milliseconds(150)

    private let taskProvider = TaskProviderSpy.tolerant()
    private let clock = TestClock()
    private let reader = ScriptedGitReader()
    private let watchers = WatcherFactory()
    private let defaultsCleanup = DefaultsCleanup()

    private static func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    private static func info(branches: [String] = ["main"]) -> RepositoryInfo {
        RepositoryInfo(root: root, branches: branches, tags: [], commits: [])
    }

    private func makeSUT() -> DiffViewerModel {
        let suite = "GitDiffViewerTests.freshness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaultsCleanup.register(suite)
        return DiffViewerModel(settings: ViewerSettings(defaults: defaults), reader: reader, taskProvider: taskProvider)
    }

    /// `HEAD` at commit `c1` against its working tree, both listing `tree`, with the watcher attached.
    private func makeLoadedSUT(tree: [SourceEntry] = [entry("a.swift", "1")]) async throws
        -> (DiffViewerModel, FakeWatchEventSource)
    {
        reader.repositories[Self.root] = Self.info()
        reader.commits = ["HEAD": "c1"]
        reader.entries[Self.head] = tree
        reader.entries[Self.tree] = tree
        let sut = makeSUT()
        sut.left.load(Self.head, repository: Self.info())
        sut.right.load(Self.tree, repository: Self.info())
        try await taskProvider.waitForAllTasks()
        sut.attachFreshness(clock: clock, makeWatcher: watchers.makeWatcher)
        let source = try #require(watchers.latest)
        try await source.waitUntilWatching(2)
        return (sut, source)
    }

    /// Reports a write at `path`, lets its debounce run out, and waits until everything it started has finished.
    private func report(_ path: String, on source: FakeWatchEventSource, after debounce: Duration) async throws {
        try #require(source.write(path))
        try await clock.waitForSleepers()
        clock.advance(by: debounce)
        try await taskProvider.waitForAllTasks()
    }

    private func drain(_ sut: DiffViewerModel) async throws {
        sut.freshness?.teardown()
        try await taskProvider.waitForAllTasks()
        try await taskProvider.waitForObservationsToFinish()
    }

    // MARK: Working-tree writes

    @Test
    func `a save made while a reload lists the tree still shows once that reload lands`() async throws {
        let (sut, source) = try await makeLoadedSUT(tree: [Self.entry("a.swift", "1"), Self.entry("b.swift", "1")])

        // Save A; its reload starts listing the tree, and the listing is held.
        reader.entries[Self.tree] = [Self.entry("a.swift", "2"), Self.entry("b.swift", "1")]
        let listing = reader.gateNextListing(of: Self.tree)
        try #require(source.write("/repo/a.swift"))
        try await clock.waitForSleepers()
        clock.advance(by: Self.treeDebounce)
        _ = try await listing.reached.next()

        // Save B while A's listing runs, then let A's listing land without B.
        reader.entries[Self.tree] = [Self.entry("a.swift", "2"), Self.entry("b.swift", "2")]
        let mark = clock.registrationMark()
        try #require(source.write("/repo/b.swift"))
        try await clock.waitForSleepers(1, after: mark)
        listing.open()
        await awaitObserved { !sut.right.isLoading }
        #expect(sut.right.entriesByPath["b.swift"]?.blobID == "1")
        try #require(watchers.all.count == 1)

        clock.advance(by: Self.treeDebounce)
        try await taskProvider.waitForAllTasks()

        #expect(sut.right.entriesByPath["b.swift"]?.blobID == "2")
        try await drain(sut)
    }
}
