import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// Each side's explorer draws a change's git state in the comparison, keyed by its own paths, so the same file draws
/// the same state in both trees (CARD-11): filled for a committed or staged change, stroked for an unstaged one.
@MainActor
@Suite(.mainActorLane)
struct ExplorerBadgeStatesTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
    private nonisolated static let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
    private nonisolated static let tree = ComparisonSource.directory(root)

    private let harness = ModelTestHarness()

    /// Parses NUL-terminated porcelain v2 records, the format ``GitClient/status(includingIgnored:)`` asks git for.
    private static func status(_ records: String...) -> [GitStatusEntry] {
        GitParsers.porcelainV2(Data((records.joined(separator: "\u{0}") + "\u{0}").utf8)).entries
    }

    /// `left` against `right`, both loaded, with `status` as the working tree's git status.
    private func makeLoadedSUT(
        left: ComparisonSource = head, right: ComparisonSource = tree, leftEntries: [SourceEntry],
        rightEntries: [SourceEntry], status: [GitStatusEntry] = []
    ) async throws -> DiffViewerModel {
        harness.reader.entries[left] = leftEntries
        harness.reader.entries[right] = rightEntries
        harness.reader.workingTreeStatuses[Self.tree] = status
        let sut = harness.makeSUT()
        sut.left.load(left, repository: Self.info)
        sut.right.load(right, repository: Self.info)
        try await harness.taskProvider.waitForAllTasks()
        return sut
    }

    @Test
    func `in HEAD against the working tree, the HEAD tree draws an unstaged edit stroked, like the tree beside it`()
        async throws
    {
        let sut = try await makeLoadedSUT(
            leftEntries: [harness.entry("Sources/a.swift", "1")], rightEntries: [harness.entry("Sources/a.swift", "2")],
            status: Self.status("1 .M N... 100644 100644 100644 aaaa aaaa Sources/a.swift"))

        #expect(sut.left.explorerBadgeStates.state(of: "Sources/a.swift") == .unstaged)
        #expect(sut.left.explorerBadgeStates.state(of: "Sources") == .unstaged)
        #expect(sut.right.explorerBadgeStates.state(of: "Sources/a.swift") == .unstaged)
    }

    @Test
    func `a staged edit and a committed one draw filled in both trees`() async throws {
        let sut = try await makeLoadedSUT(
            leftEntries: [harness.entry("staged.swift", "1"), harness.entry("committed.swift", "1")],
            rightEntries: [harness.entry("staged.swift", "2"), harness.entry("committed.swift", "2")],
            status: Self.status("1 M. N... 100644 100644 100644 aaaa bbbb staged.swift"))

        for explorer in [sut.left.explorerBadgeStates, sut.right.explorerBadgeStates] {
            #expect(explorer.state(of: "staged.swift") == .staged)
            #expect(explorer.state(of: "committed.swift") == .staged)
        }
    }

    @Test
    func `a renamed file draws one state in both trees, each under its own path and in its own folders`() async throws {
        harness.reader.gitRenames = ["Sources/old.swift": "Moved/old.swift"]
        let sut = try await makeLoadedSUT(
            leftEntries: [harness.entry("Sources/old.swift", "1"), harness.entry("Sources/kept.swift", "2")],
            rightEntries: [harness.entry("Moved/old.swift", "1b"), harness.entry("Sources/kept.swift", "2")],
            status: Self.status(
                "2 RM N... 100644 100644 100644 aaaa bbbb R90 Moved/old.swift", "Sources/old.swift"))

        #expect(sut.left.explorerBadgeStates.state(of: "Sources/old.swift") == .unstaged)
        #expect(sut.left.explorerBadgeStates.state(of: "Sources") == .unstaged)
        #expect(sut.right.explorerBadgeStates.state(of: "Moved/old.swift") == .unstaged)
        #expect(sut.right.explorerBadgeStates.state(of: "Moved") == .unstaged)
        #expect(sut.right.explorerBadgeStates.state(of: "Sources") == .staged)
    }

    @Test
    func `a rename made without git, a deleted path and an untracked one, draws one state in both trees`()
        async throws
    {
        let sut = try await makeLoadedSUT(
            leftEntries: [harness.entry("old.swift", "1")], rightEntries: [harness.entry("new.swift", "1")],
            status: Self.status("1 .D N... 100644 100644 000000 aaaa aaaa old.swift", "? new.swift"))

        #expect(sut.left.explorerBadgeStates.state(of: "old.swift") == .unstaged)
        #expect(sut.right.explorerBadgeStates.state(of: "new.swift") == .unstaged)
    }

    @Test
    func `a ref against a ref draws every change filled in both trees`() async throws {
        let feature = ComparisonSource.gitRef(repository: Self.root, ref: "feature")
        let sut = try await makeLoadedSUT(
            right: feature, leftEntries: [harness.entry("a.swift", "1")], rightEntries: [harness.entry("a.swift", "2")])

        #expect(sut.left.explorerBadgeStates.state(of: "a.swift") == .staged)
        #expect(sut.right.explorerBadgeStates.state(of: "a.swift") == .staged)
    }

    @Test
    func `merging keys one side's tree by its own paths and follows the other side's files to them`() {
        let working = BadgeChangeStates(status: Self.status("1 .M N... 100644 100644 100644 aaaa aaaa Moved/old.swift"))

        let headTree = BadgeChangeStates.merged(.uniform(.staged), with: working) {
            $0 == "Moved/old.swift" ? "Sources/old.swift" : $0
        }

        #expect(headTree.state(of: "Sources/old.swift") == .unstaged)
        #expect(headTree.state(of: "Sources") == .unstaged)
        #expect(headTree.state(of: "Moved") == .staged)
    }
}
