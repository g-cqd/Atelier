import AemiCore
import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``SideState/refreshRepositoryInfo()``: re-reads repository info without touching entries.
@MainActor
struct SideStateFreshnessTests {
    private static let root = URL(filePath: "/repo", directoryHint: .isDirectory)

    private func makeSUT(reader: FakeSourceReader, taskProvider: TaskProviderSpy) -> SideState {
        SideState(label: "Right", reader: reader, taskProvider: taskProvider)
    }

    @Test
    func `refreshRepositoryInfo replaces repository with a freshly read one`() async throws {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy.tolerant()
        let initial = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        reader.repositories[Self.root] = initial
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)
        sut.load(.directory(Self.root), repository: initial)
        try await taskProvider.waitForAllTasks()
        #expect(sut.repository?.branches == ["main"])

        let refreshed = RepositoryInfo(root: Self.root, branches: ["main", "feature"], tags: [], commits: [])
        reader.repositories[Self.root] = refreshed

        await sut.refreshRepositoryInfo()

        #expect(sut.repository?.branches == ["main", "feature"])
    }

    @Test
    func `refreshRepositoryInfo does nothing before a source is chosen`() async {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy.tolerant()
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)

        await sut.refreshRepositoryInfo()

        #expect(sut.repository == nil)
    }

    @Test
    func `refreshRepositoryInfo keeps the previous value when the reader cannot resolve the root`() async throws {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy.tolerant()
        let initial = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        reader.repositories[Self.root] = initial
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)
        sut.load(.directory(Self.root), repository: initial)
        try await taskProvider.waitForAllTasks()

        reader.repositories[Self.root] = nil

        await sut.refreshRepositoryInfo()

        #expect(sut.repository?.branches == ["main"])
    }

    @Test
    func `refreshRepositoryInfo never publishes over a repository this side has since moved away from`() async throws {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy.tolerant()
        let repoA = URL(filePath: "/repoA", directoryHint: .isDirectory)
        let repoB = URL(filePath: "/repoB", directoryHint: .isDirectory)
        let initialA = RepositoryInfo(root: repoA, branches: ["main"], tags: [], commits: [])
        let initialB = RepositoryInfo(root: repoB, branches: ["develop"], tags: [], commits: [])
        reader.repositories[repoA] = initialA
        reader.repositories[repoB] = initialB
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)
        sut.load(.directory(repoA), repository: initialA)
        try await taskProvider.waitForAllTasks()

        // A's re-read is gated and confirmed started before the side moves on to B.
        reader.gate["repositoryInfo:\(repoA.path(percentEncoded: false))"] = AsyncProbe<Void>()
        taskProvider.task { await sut.refreshRepositoryInfo() }
        _ = try await reader.repositoryInfoRequests.next()

        sut.load(.directory(repoB), repository: initialB)
        reader.gate["repositoryInfo:\(repoA.path(percentEncoded: false))"]?.send(())
        try await taskProvider.waitForAllTasks()

        // A's stale read must never overwrite B's already-published info.
        #expect(sut.repository?.root == repoB)
        #expect(sut.repository?.branches == ["develop"])
    }
}
