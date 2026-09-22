import AemiTesting
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``DiffViewerModel/attachFreshness()``'s fetch wiring: a fetch that lands on a side parked on a remote-tracking
/// ref re-runs the comparison against the moved ref, the way a manual reload would; a fetch on a local branch
/// does not. Exercised through a real ``SideState/fetch()`` against a fake runner, not a synthetic callback, so
/// the whole chain -- runner, remotes, fetch, refresh, re-compare -- is what is actually under test.
@MainActor
struct DiffViewerModelFetchTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)

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
        FakeProcessRunner { spec in
            if spec.arguments.contains("fetch") { return .success("") }
            if spec.arguments.contains("remote") { return .success("origin\tgit@example.com:x.git (fetch)\n") }
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

    private func makeSUT(runner: any ProcessRunner, taskProvider: TaskProviderSpy) -> (DiffViewerModel, () -> Void) {
        let suite = "GitDiffViewerTests.fetch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = DiffViewerModel(
            settings: ViewerSettings(defaults: defaults), reader: SourceLoader(runner: runner),
            taskProvider: taskProvider)
        return (model, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test
    func `a fetch on a side parked on a remote-tracking ref reloads the comparison`() async throws {
        let taskProvider = TaskProviderSpy()
        let tree = RemoteTree()
        let (sut, cleanup) = makeSUT(runner: makeRunner(tree: tree), taskProvider: taskProvider)
        defer { cleanup() }
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
    func `a fetch on a side parked on a local branch does not reload the comparison`() async throws {
        let taskProvider = TaskProviderSpy()
        let tree = RemoteTree()
        let (sut, cleanup) = makeSUT(runner: makeRunner(tree: tree), taskProvider: taskProvider)
        defer { cleanup() }
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main", "origin/develop"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "main"), repository: repository)
        sut.right.load(.gitRef(repository: Self.root, ref: "main"), repository: repository)
        try await taskProvider.waitForAllTasks()
        #expect(sut.left.entries.map(\.relativePath) == ["right.txt"])

        tree.move(to: "b.swift")
        await sut.right.fetch()
        try await taskProvider.waitForAllTasks()

        // Still "right.txt": fetching moved no remote-tracking ref either side is parked on, so neither side
        // reloads and `main`'s own (unmoved) tree is what both keep showing.
        #expect(sut.left.entries.map(\.relativePath) == ["right.txt"])
    }
}
