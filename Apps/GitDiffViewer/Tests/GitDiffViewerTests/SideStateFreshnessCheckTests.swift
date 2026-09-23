import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The listing filter one side applies to the watcher's working-tree writes: git is asked about unlisted paths
/// alone (GDV S2).
@MainActor
struct SideStateFreshnessCheckTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
    private nonisolated static let tree = ComparisonSource.directory(root)

    private let reader = ScriptedGitReader()
    private let taskProvider = TaskProviderSpy.tolerant()

    private func makeSUT() -> SideState {
        SideState(label: "Right", reader: reader, taskProvider: taskProvider)
    }

    private static func entry(_ path: String, _ blob: String = "1") -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    /// A working tree loaded with its ignored files listed once.
    private func makeTreeWithIgnoredFiles() async throws -> SideState {
        reader.entries[Self.tree] = [Self.entry("a.swift")]
        reader.ignoredEntries[Self.tree] = [SourceEntry(relativePath: "build/out.txt", blobID: nil, size: 0)]
        let sut = makeSUT()
        sut.load(Self.tree, repository: Self.info)
        try await taskProvider.waitForAllTasks()
        sut.loadIgnoredEntries()
        try await taskProvider.waitForAllTasks()
        return sut
    }

    // MARK: The listing filter (GDV S2)

    @Test
    func `a write to a listed file changes the listing without asking git`() async throws {
        let sut = try await makeTreeWithIgnoredFiles()

        #expect(await sut.listingMayChange(at: ["a.swift", "build/out.o"]))
        #expect(reader.ignoreChecks.isEmpty)
    }

    @Test
    func `writes git ignores leave the listing as it is`() async throws {
        let sut = try await makeTreeWithIgnoredFiles()
        reader.ignoredPaths = ["build/Generated.swift", "build/app"]

        #expect(await !sut.listingMayChange(at: ["build/Generated.swift", "build/app"]))
        #expect(reader.ignoreChecks == [["build/Generated.swift", "build/app"]])
    }

    @Test
    func `a check-ignore that fails counts as a change, so no edit is missed`() async throws {
        let sut = try await makeTreeWithIgnoredFiles()
        reader.ignoreCheckFailure = "fatal: not a git repository"

        #expect(await sut.listingMayChange(at: ["build/Generated.swift"]))
    }
}
