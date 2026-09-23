import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// Per-path badge states through the model: every explorer's lookup, a rename followed to its left-side path, and an
/// index change that re-reads git's status without reloading the files.
@MainActor
struct DiffViewerModelBadgeStatesTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
    private nonisolated static let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
    private nonisolated static let tree = ComparisonSource.directory(root)

    private let harness = ModelTestHarness()

    /// Parses NUL-terminated porcelain v2 records, the format ``GitClient/status()`` asks git for.
    private static func status(_ records: String...) -> [GitStatusEntry] {
        GitParsers.porcelainV2(Data((records.joined(separator: "\u{0}") + "\u{0}").utf8)).entries
    }

    /// `HEAD` against its working tree, both loaded, with `status` as the working tree's git status.
    private func makeLoadedSUT(head: [SourceEntry], tree: [SourceEntry], status: [GitStatusEntry]) async throws
        -> DiffViewerModel
    {
        harness.reader.entries[Self.head] = head
        harness.reader.entries[Self.tree] = tree
        harness.reader.workingTreeStatuses[Self.tree] = status
        let sut = harness.makeSUT()
        sut.left.load(Self.head, repository: Self.info)
        sut.right.load(Self.tree, repository: Self.info)
        try await harness.taskProvider.waitForAllTasks()
        return sut
    }

    @Test
    func `each explorer looks up its own paths, and the unified one follows a rename to its left-side folder`()
        async throws
    {
        harness.reader.gitRenames = ["Sources/old.swift": "Moved/old.swift"]
        let sut = try await makeLoadedSUT(
            head: [
                harness.entry("Sources/old.swift", "1"), harness.entry("Sources/kept.swift", "2"),
                harness.entry("Docs/readme.md", "3"), harness.entry("Docs/guide.md", "5")
            ],
            tree: [
                harness.entry("Moved/old.swift", "1b"), harness.entry("Sources/kept.swift", "2b"),
                harness.entry("Docs/readme.md", "3b"), harness.entry("Docs/guide.md", "5"),
                harness.entry("new.swift", "4")
            ],
            status: Self.status(
                "2 RM N... 100644 100644 100644 aaaa bbbb R90 Moved/old.swift", "Sources/old.swift",
                "1 M. N... 100644 100644 100644 aaaa bbbb Sources/kept.swift",
                "1 .M N... 100644 100644 100644 aaaa aaaa Docs/readme.md", "? new.swift"))

        #expect(sut.badgeState(ofPath: "Sources/old.swift") == .unstaged)
        #expect(sut.badgeState(ofPath: "Sources") == .unstaged)
        #expect(sut.badgeState(ofPath: "Moved") == .staged)
        #expect(sut.badgeState(ofPath: "Sources/kept.swift") == .staged)
        #expect(sut.badgeState(ofPath: "Docs/readme.md") == .unstaged)
        #expect(sut.badgeState(ofPath: "Docs/guide.md") == .staged)
        #expect(sut.badgeState(ofPath: "new.swift") == .untracked)
        #expect(sut.right.badgeState(of: "Moved/old.swift") == .unstaged)
        #expect(sut.right.badgeState(of: "Moved") == .unstaged)
        #expect(sut.left.badgeState(of: "Sources/old.swift") == .staged)
    }

    @Test
    func `an index change re-reads git's status and every lookup follows, with no file listed again`() async throws {
        let sut = try await makeLoadedSUT(
            head: [harness.entry("a.swift", "1")], tree: [harness.entry("a.swift", "2")],
            status: Self.status("1 .M N... 100644 100644 100644 aaaa aaaa a.swift"))
        sut.attachFreshness()
        #expect(sut.badgeState(ofPath: "a.swift") == .unstaged)
        let listingsBefore = harness.reader.entriesReads

        harness.reader.workingTreeStatuses[Self.tree] = Self.status("1 M. N... 100644 100644 100644 aaaa bbbb a.swift")
        sut.freshness?.onIndexChanged?()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.badgeState(ofPath: "a.swift") == .staged)
        #expect(sut.right.badgeState(of: "a.swift") == .staged)
        #expect(harness.reader.entriesReads == listingsBefore)
        sut.freshness?.teardown()
        try await harness.taskProvider.waitForAllTasks()
        try await harness.taskProvider.waitForObservationsToFinish()
    }

    @Test
    func `comparing a repository's working tree reads its git status in the same pass as its files`() async throws {
        harness.reader.repositories[Self.root] = Self.info
        harness.reader.entries[Self.head] = [harness.entry("a.swift", "1")]
        harness.reader.entries[Self.tree] = [harness.entry("a.swift", "2")]
        harness.reader.workingTreeStatuses[Self.tree] = Self.status("1 .M N... 100644 100644 100644 aaaa aaaa a.swift")
        let sut = harness.makeSUT()

        sut.compareGitChanges(in: Self.root)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.badgeState(ofPath: "a.swift") == .unstaged)
        #expect(try await harness.reader.workingTreeStatusRequests.expectNext() == Self.tree)
        try harness.reader.workingTreeStatusRequests.expectNoBufferedElements()
        #expect(harness.reader.entriesReads == 2)
    }
}
