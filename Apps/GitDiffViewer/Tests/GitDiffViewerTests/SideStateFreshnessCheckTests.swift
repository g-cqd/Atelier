import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// What one side re-reads after an outside change: the ignored files it keeps across a watcher's reload (GDV S13),
/// the ref check that reloads only when the commit moved (GDV S3), and the listing filter that asks git about
/// unlisted paths alone (GDV S2).
@MainActor
struct SideStateFreshnessCheckTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
    private nonisolated static let tree = ComparisonSource.directory(root)
    private nonisolated static let main = ComparisonSource.gitRef(repository: root, ref: "main")

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

    // MARK: Ignored files (GDV S13)

    @Test
    func `a reload after an outside write keeps the ignored files it listed and lists them no more`() async throws {
        let sut = try await makeTreeWithIgnoredFiles()
        let listingsBefore = reader.ignoredListings

        sut.reload(keepingIgnoredEntries: true)
        try await taskProvider.waitForAllTasks()

        #expect(sut.ignoredEntries?.map(\.relativePath) == ["build/out.txt"])
        #expect(reader.ignoredListings == listingsBefore)
    }

    @Test
    func `a reload the user asks for lists the ignored files anew`() async throws {
        let sut = try await makeTreeWithIgnoredFiles()

        sut.reload()
        try await taskProvider.waitForAllTasks()

        #expect(sut.ignoredEntries == nil)
    }

    @Test
    func `a failed listing of the ignored files says why instead of leaving a silent empty section`() async throws {
        reader.ignoredListingFailure = "fatal: unable to read the index"

        let sut = try await makeTreeWithIgnoredFiles()

        #expect(sut.ignoredEntries?.isEmpty == true)
        #expect(sut.errorMessage == "Ignored files: fatal: unable to read the index")
    }

    @Test
    func `a reload that keeps the ignored files keeps saying why their listing failed`() async throws {
        reader.ignoredListingFailure = "fatal: unable to read the index"
        let sut = try await makeTreeWithIgnoredFiles()

        sut.reload(keepingIgnoredEntries: true)
        try await taskProvider.waitForAllTasks()

        #expect(sut.errorMessage == "Ignored files: fatal: unable to read the index")
    }

    // MARK: Ref checks (GDV S3)

    /// A side on `main` at commit `c1`, listed through its own load.
    private func makeSideOnMain() async throws -> SideState {
        reader.commits = ["main": "c1"]
        reader.entries[Self.main] = [Self.entry("a.swift")]
        let sut = makeSUT()
        sut.load(Self.main, repository: Self.info)
        try await taskProvider.waitForAllTasks()
        return sut
    }

    @Test
    func `a load resolves a ref before listing its tree and keeps the commit`() async throws {
        let sut = try await makeSideOnMain()

        #expect(sut.resolvedCommit == "c1")
    }

    @Test
    func `a ref still naming the commit its entries were listed at reloads nothing`() async throws {
        let sut = try await makeSideOnMain()
        let listings = reader.listings(of: Self.main)

        sut.reloadIfRefMoved()
        try await taskProvider.waitForAllTasks()

        #expect(reader.listings(of: Self.main) == listings)
    }

    @Test
    func `a ref that moved reloads, and the reload keeps the new commit`() async throws {
        let sut = try await makeSideOnMain()
        reader.commits = ["main": "c2"]
        reader.entries[Self.main] = [Self.entry("a.swift", "2")]

        sut.reloadIfRefMoved()
        try await taskProvider.waitForAllTasks()

        #expect(sut.entriesByPath["a.swift"]?.blobID == "2")
        #expect(sut.resolvedCommit == "c2")
    }

    @Test
    func `two notices of one move reload once`() async throws {
        let sut = try await makeSideOnMain()
        let listings = reader.listings(of: Self.main)
        reader.commits = ["main": "c2"]

        sut.reloadIfRefMoved()
        sut.reloadIfRefMoved()
        try await taskProvider.waitForAllTasks()

        #expect(reader.listings(of: Self.main) == listings + 1)
    }

    @Test
    func `a side handed its entries without their commit reloads once to learn it`() async throws {
        reader.commits = ["main": "c1"]
        reader.entries[Self.main] = [Self.entry("a.swift")]
        let sut = makeSUT()
        sut.load(Self.main, repository: Self.info, entries: [Self.entry("a.swift")])

        sut.reloadIfRefMoved()
        try await taskProvider.waitForAllTasks()
        sut.reloadIfRefMoved()
        try await taskProvider.waitForAllTasks()

        #expect(reader.listings(of: Self.main) == 1)
        #expect(sut.resolvedCommit == "c1")
    }

    @Test
    func `a working tree has no ref to check`() async throws {
        reader.entries[Self.tree] = [Self.entry("a.swift")]
        let sut = makeSUT()
        sut.load(Self.tree, repository: Self.info)
        try await taskProvider.waitForAllTasks()
        let spawned = taskProvider.spawnedTaskCount

        sut.reloadIfRefMoved()

        #expect(taskProvider.spawnedTaskCount == spawned)
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
