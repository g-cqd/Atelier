import AemiTesting
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``DiffViewerModel/attachFreshness()``'s refs-changed wiring: an ordinary commit moves `refs/heads/<branch>`
/// without touching the symbolic `.git/HEAD` file, so ``RepositoryFreshness/onHeadChanged`` never fires for it --
/// only ``RepositoryFreshness/onRefsChanged``. A side parked on a named ref (`HEAD`, a branch, a remote-tracking
/// ref) must still pick up wherever that ref now points, not just refresh its menu.
@MainActor
struct DiffViewerModelRefsChangedTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)

    private nonisolated static func treeOutput(path: String) -> ProcessOutput {
        .success("100644 blob deadbeef 3\t\(path)")
    }

    /// What `HEAD`'s tree listing serves, changed between the initial load and the refs-changed callback so a
    /// test can simulate a commit landing on the checked-out branch.
    private final class HeadTree: Sendable {
        private let path = Mutex("a.swift")
        var current: String { path.withLock { $0 } }
        func move(to newPath: String) { path.withLock { $0 = newPath } }
    }

    private nonisolated func makeRunner(headTree: HeadTree) -> FakeProcessRunner {
        FakeProcessRunner { spec in
            if spec.arguments.contains("rev-parse") { return .success(Self.root.path(percentEncoded: false)) }
            if spec.arguments.contains("for-each-ref") { return .success("main\n") }
            if spec.arguments.contains("log") { return .success("") }
            if spec.arguments.contains("ls-tree") {
                let ref = spec.arguments.last ?? ""
                return Self.treeOutput(path: ref == "HEAD" ? headTree.current : "right.txt")
            }
            return .success("")
        }
    }

    private func makeSUT(runner: any ProcessRunner, taskProvider: TaskProviderSpy) -> (DiffViewerModel, () -> Void) {
        let suite = "GitDiffViewerTests.refsChanged.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = DiffViewerModel(
            settings: ViewerSettings(defaults: defaults), reader: SourceLoader(runner: runner),
            taskProvider: taskProvider)
        return (model, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test
    func `a refs change recomposes a HEAD-versus-working-tree comparison, picking up the new commit`() async throws {
        let taskProvider = TaskProviderSpy()
        let headTree = HeadTree()
        let (sut, cleanup) = makeSUT(runner: makeRunner(headTree: headTree), taskProvider: taskProvider)
        defer { cleanup() }
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "HEAD"), repository: repository)
        sut.right.load(.directory(Self.root), repository: repository)
        try await taskProvider.waitForAllTasks()
        #expect(sut.left.entries.map(\.relativePath) == ["a.swift"])

        // A commit landed on the checked-out branch: `refs/heads/main` moved, `.git/HEAD` itself did not, so
        // `RepositoryFreshness` reports this through `onRefsChanged`, not `onHeadChanged`.
        headTree.move(to: "b.swift")
        sut.freshness?.onRefsChanged?()
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.entries.map(\.relativePath) == ["b.swift"])
    }

    @Test
    func `a refs change with both sides on the working tree only refreshes repository info`() async throws {
        let taskProvider = TaskProviderSpy()
        let headTree = HeadTree()
        let (sut, cleanup) = makeSUT(runner: makeRunner(headTree: headTree), taskProvider: taskProvider)
        defer { cleanup() }
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        sut.left.load(.directory(Self.root), repository: repository)
        sut.right.load(.directory(Self.root), repository: repository)
        try await taskProvider.waitForAllTasks()
        let spawnedBefore = taskProvider.spawnedTaskCount

        sut.freshness?.onRefsChanged?()
        try await taskProvider.waitForAllTasks()

        // Neither side names a ref, so a refs change cannot have moved what either is showing: the cheap,
        // single-task menu refresh runs (`refreshBothSidesRepositoryInfo`'s own `taskProvider.task`), not
        // `reloadSources()`'s two (one per side).
        #expect(taskProvider.spawnedTaskCount - spawnedBefore == 1)
    }
}
