import AemiTesting
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The refs-changed wiring: a commit moves the branch's ref but not the symbolic `.git/HEAD`, so a side parked on a
/// named ref must reload on a refs change, not just refresh its menu.
@MainActor
struct DiffViewerModelRefsChangedTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private let scratchDefaults = ScratchDefaults(tag: "refsChanged")

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
            // HEAD's commit moves with the tree a commit leaves behind.
            if spec.arguments.contains("--verify") { return .success("commit-\(headTree.current)\n") }
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

    private func makeSUT(runner: any ProcessRunner, taskProvider: TaskProviderSpy) -> DiffViewerModel {
        DiffViewerModel(
            settings: ViewerSettings(defaults: scratchDefaults.defaults),
            reader: SourceLoader(runner: runner, pool: LoaderTestPool.shared),
            taskProvider: taskProvider)
    }

    @Test
    func `a refs change recomposes a HEAD-versus-working-tree comparison, picking up the new commit`() async throws {
        let taskProvider = TaskProviderSpy.tolerant()
        let headTree = HeadTree()
        let sut = makeSUT(runner: makeRunner(headTree: headTree), taskProvider: taskProvider)
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        sut.left.load(.gitRef(repository: Self.root, ref: "HEAD"), repository: repository)
        sut.right.load(.directory(Self.root), repository: repository)
        try await taskProvider.waitForAllTasks()
        #expect(sut.left.entries.map(\.relativePath) == ["a.swift"])

        // A commit on the checked-out branch moves `refs/heads/main`, which arrives as a refs change.
        headTree.move(to: "b.swift")
        sut.freshness?.onRefsChanged?()
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.entries.map(\.relativePath) == ["b.swift"])
    }

    @Test
    func `a refs change with both sides on the working tree only refreshes repository info`() async throws {
        let taskProvider = TaskProviderSpy.tolerant()
        let headTree = HeadTree()
        let sut = makeSUT(runner: makeRunner(headTree: headTree), taskProvider: taskProvider)
        sut.attachFreshness()

        let repository = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        sut.left.load(.directory(Self.root), repository: repository)
        sut.right.load(.directory(Self.root), repository: repository)
        try await taskProvider.waitForAllTasks()
        let spawnedBefore = taskProvider.spawnedTaskCount

        sut.freshness?.onRefsChanged?()
        try await taskProvider.waitForAllTasks()

        // Neither side names a ref: one menu-refresh task runs instead of a reload's two.
        #expect(taskProvider.spawnedTaskCount - spawnedBefore == 1)
    }
}
