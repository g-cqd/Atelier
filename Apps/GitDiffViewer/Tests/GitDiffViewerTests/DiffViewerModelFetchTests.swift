import AemiTesting
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The fetch wiring: a fetch re-runs the comparison when a side is parked on a remote-tracking ref, and not for a
/// local branch; driven through a real ``SideState/fetch()`` over a fake runner.
@MainActor
@Suite(.mainActorLane)
struct DiffViewerModelFetchTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private let scratchDefaults = ScratchDefaults(tag: "fetch")

    private nonisolated static func treeOutput(path: String) -> ProcessOutput {
        .success("100644 blob deadbeef 3\t\(path)")
    }

    /// What the `origin/develop` tree listing serves, changed between the initial load and the fetch so a test
    /// can simulate the remote moving.
    private final class RemoteTree: Sendable {
        private let path = Mutex("a.swift")
        var current: String { path.withLock { $0 } }
        func move(to newPath: String) { path.withLock { $0 = newPath } }
    }

    private nonisolated func makeRunner(tree: RemoteTree) -> FakeProcessRunner {
        FakeProcessRunner.gated(remotes: ["origin": "git@example.com:x.git"]) { spec in
            if spec.arguments.contains("fetch") { return .success("") }
            if spec.arguments.contains("remote") { return .success("origin\tgit@example.com:x.git (fetch)\n") }
            // A remote-tracking ref's commit moves with its tree; every other ref stays put.
            if spec.arguments.contains("--verify") {
                let isRemote = spec.arguments.last?.hasPrefix("origin/develop") == true
                return .success(isRemote ? "commit-\(tree.current)\n" : "commit-main\n")
            }
            if spec.arguments.contains("rev-parse") { return .success(Self.root.path(percentEncoded: false)) }
            if spec.arguments.contains("for-each-ref") { return .success("main\norigin/develop\n") }
            if spec.arguments.contains("log") { return .success("") }
            if spec.arguments.contains("ls-tree") {
                let ref = spec.arguments.last ?? ""
                return Self.treeOutput(path: ref == "origin/develop" ? tree.current : "right.txt")
            }
            return .success("")
        }
    }

    private func makeSUT(runner: any ProcessRunner, taskProvider: TaskProviderSpy) -> DiffViewerModel {
        DiffViewerModel(
            settings: ViewerSettings(defaults: scratchDefaults.defaults),
            reader: SourceLoader(runner: runner, pool: LoaderTestPool.shared),
            taskProvider: taskProvider)
    }

    @Test
    func `a fetch on a side parked on a remote-tracking ref reloads the comparison`() async throws {
        let taskProvider = TaskProviderSpy.tolerant()
        let tree = RemoteTree()
        let sut = makeSUT(runner: makeRunner(tree: tree), taskProvider: taskProvider)
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main", "origin/develop"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "origin/develop"), repository: repository)
        sut.right.load(.gitRef(repository: Self.root, ref: "main"), repository: repository)
        try await taskProvider.waitForAllTasks()
        #expect(sut.left.entries.map(\.relativePath) == ["a.swift"])

        tree.move(to: "b.swift")
        await sut.left.fetch()
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.entries.map(\.relativePath) == ["b.swift"])
    }

    @Test
    func `a fetch that moves the tracked ref reloads that side once, the watcher's notice of the same refs included`()
        async throws
    {
        let taskProvider = TaskProviderSpy.tolerant()
        let tree = RemoteTree()
        let runner = makeRunner(tree: tree)
        let sut = makeSUT(runner: runner, taskProvider: taskProvider)
        let clock = TestClock()
        let watchers = WatcherFactory()
        sut.attachFreshness(clock: clock, makeWatcher: watchers.makeWatcher)
        let repository = RepositoryInfo(root: Self.root, branches: ["main", "origin/develop"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "origin/develop"), repository: repository)
        sut.right.load(.directory(Self.root), repository: repository)
        try await taskProvider.waitForAllTasks()
        let source = try #require(watchers.latest)
        try await source.waitUntilWatching(2)
        func remoteListings() -> Int {
            runner.commandSpecs.count { $0.arguments.contains("ls-tree") && $0.arguments.last == "origin/develop" }
        }
        let listingsBefore = remoteListings()

        tree.move(to: "b.swift")
        await sut.left.fetch()
        try await taskProvider.waitForAllTasks()
        // The fetch moved the remote-tracking ref on disk, which the watcher reports as well.
        let mark = clock.registrationMark()
        try #require(source.write("/repo/.git/refs/remotes/origin/develop"))
        try await clock.expectSleepers(after: mark)
        clock.advance(by: .milliseconds(150))
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.entries.map(\.relativePath) == ["b.swift"])
        #expect(remoteListings() == listingsBefore + 1)
        sut.freshness?.teardown()
        try await taskProvider.waitForAllTasks()
        try await taskProvider.waitForObservationsToFinish()
    }

    @Test
    func `a fetch on a side parked on a local branch does not reload the comparison`() async throws {
        let taskProvider = TaskProviderSpy.tolerant()
        let tree = RemoteTree()
        let sut = makeSUT(runner: makeRunner(tree: tree), taskProvider: taskProvider)
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main", "origin/develop"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "main"), repository: repository)
        sut.right.load(.gitRef(repository: Self.root, ref: "main"), repository: repository)
        try await taskProvider.waitForAllTasks()
        #expect(sut.left.entries.map(\.relativePath) == ["right.txt"])

        tree.move(to: "b.swift")
        await sut.right.fetch()
        try await taskProvider.waitForAllTasks()

        // Still "right.txt": neither side is parked on a remote-tracking ref, so neither reloads.
        #expect(sut.left.entries.map(\.relativePath) == ["right.txt"])
    }
}
