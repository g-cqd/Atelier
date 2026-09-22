import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``SideState/refreshRepositoryInfo()``: re-reads repository info without touching entries, the seam
/// ``RepositoryFreshness``'s refs callback (and, later, a fetch) drives.
@MainActor
struct SideStateFreshnessTests {
    private static let root = URL(filePath: "/repo", directoryHint: .isDirectory)

    private func makeSUT(reader: FakeSourceReader, taskProvider: TaskProviderSpy) -> SideState {
        SideState(label: "Right", reader: reader, taskProvider: taskProvider)
    }

    @Test
    func `refreshRepositoryInfo replaces repository with a freshly read one`() async throws {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy()
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
        let taskProvider = TaskProviderSpy()
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)

        await sut.refreshRepositoryInfo()

        #expect(sut.repository == nil)
    }

    @Test
    func `refreshRepositoryInfo keeps the previous value when the reader cannot resolve the root`() async throws {
        let reader = FakeSourceReader()
        let taskProvider = TaskProviderSpy()
        let initial = RepositoryInfo(root: Self.root, branches: ["main"], tags: [], commits: [])
        reader.repositories[Self.root] = initial
        let sut = makeSUT(reader: reader, taskProvider: taskProvider)
        sut.load(.directory(Self.root), repository: initial)
        try await taskProvider.waitForAllTasks()

        reader.repositories[Self.root] = nil

        await sut.refreshRepositoryInfo()

        #expect(sut.repository?.branches == ["main"])
    }
}
