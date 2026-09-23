import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``SideState/badgeStates``: git's status read beside every load, read again alone when the index moves, and never
/// overwritten by a read that a newer one superseded.
@MainActor
struct SideStateBadgeStatesTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])

    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()

    private func makeSUT() -> SideState {
        SideState(label: "Right", reader: reader, taskProvider: taskProvider)
    }

    /// Parses NUL-terminated porcelain v2 records, the format ``GitClient/status()`` asks git for.
    private static func status(_ records: String...) -> [GitStatusEntry] {
        GitParsers.porcelainV2(Data((records.joined(separator: "\u{0}") + "\u{0}").utf8)).entries
    }

    private static func entries(_ paths: String...) -> [SourceEntry] {
        paths.map { SourceEntry(relativePath: $0, blobID: $0, size: 1) }
    }

    /// The key ``FakeSourceReader`` gates a folder's listing under, and its git status under with `status:` first.
    private static func gateKey(_ source: ComparisonSource) -> String {
        guard case .directory(let url) = source else { return "" }
        return url.path(percentEncoded: false)
    }

    @Test
    func `a working tree's load gives each file and folder the state git reports`() async throws {
        reader.entries[.directory(Self.root)] = Self.entries(
            "edited.swift", "staged.swift", "new.swift", "dir/both.swift", "committed.swift")
        reader.workingTreeStatuses[.directory(Self.root)] = Self.status(
            "1 .M N... 100644 100644 100644 aaaa aaaa edited.swift",
            "1 M. N... 100644 100644 100644 aaaa bbbb staged.swift", "? new.swift",
            "1 MM N... 100644 100644 100644 aaaa bbbb dir/both.swift")
        let sut = makeSUT()

        sut.load(.directory(Self.root), repository: Self.info)
        try await taskProvider.waitForAllTasks()

        #expect(sut.badgeState(of: "edited.swift") == .unstaged)
        #expect(sut.badgeState(of: "staged.swift") == .staged)
        #expect(sut.badgeState(of: "new.swift") == .untracked)
        #expect(sut.badgeState(of: "dir/both.swift") == .unstaged)
        #expect(sut.badgeState(of: "dir") == .unstaged)
        #expect(sut.badgeState(of: "committed.swift") == .staged)
    }

    @Test(arguments: [
        (
            ComparisonSource.gitRef(repository: URL(filePath: "/repo", directoryHint: .isDirectory), ref: "main"),
            BadgeChangeState.staged
        ),
        (.patch(URL(filePath: "/changes.diff"), side: .new), .staged),
        (.directory(URL(filePath: "/plain", directoryHint: .isDirectory)), .unstaged)
    ])
    func `a side git reports nothing about keeps one state for every path`(
        source: ComparisonSource, state: BadgeChangeState
    ) async throws {
        let sut = makeSUT()

        sut.load(source, repository: nil)
        try await taskProvider.waitForAllTasks()

        #expect(sut.badgeState(of: "any.swift") == state)
    }

    @Test
    func `a folder that moves to another tree drops the previous tree's states before its own land`() async throws {
        let other = ComparisonSource.directory(URL(filePath: "/other", directoryHint: .isDirectory))
        reader.entries[.directory(Self.root)] = Self.entries("a.swift")
        reader.workingTreeStatuses[.directory(Self.root)] = Self.status(
            "1 M. N... 100644 100644 100644 aaaa bbbb a.swift")
        let sut = makeSUT()
        sut.load(.directory(Self.root), repository: Self.info)
        try await taskProvider.waitForAllTasks()
        #expect(sut.badgeState(of: "a.swift") == .staged)
        reader.gate[Self.gateKey(other)] = AsyncProbe<Void>()

        sut.load(other, repository: nil)

        #expect(sut.badgeState(of: "a.swift") == .unstaged)
        reader.gate[Self.gateKey(other)]?.send(())
        try await taskProvider.waitForAllTasks()
    }

    @Test
    func `refreshing reads git's status alone, so staging a file fills its badge without a reload`() async throws {
        reader.entries[.directory(Self.root)] = Self.entries("edited.swift")
        reader.workingTreeStatuses[.directory(Self.root)] = Self.status(
            "1 .M N... 100644 100644 100644 aaaa aaaa edited.swift")
        let sut = makeSUT()
        sut.load(.directory(Self.root), repository: Self.info)
        try await taskProvider.waitForAllTasks()
        let listingsBefore = reader.entriesReads
        var entriesChanges = 0
        sut.onEntriesChanged = { entriesChanges += 1 }

        reader.workingTreeStatuses[.directory(Self.root)] = Self.status(
            "1 M. N... 100644 100644 100644 aaaa bbbb edited.swift")
        sut.refreshBadgeStates()
        try await taskProvider.waitForAllTasks()

        #expect(sut.badgeState(of: "edited.swift") == .staged)
        #expect(reader.entriesReads == listingsBefore)
        #expect(entriesChanges == 0)
    }

    @Test
    func `a reload's status read that a later refresh superseded never lands over the refresh's answer`() async throws {
        let source = ComparisonSource.directory(Self.root)
        let unstaged = Self.status("1 .M N... 100644 100644 100644 aaaa aaaa a.swift")
        let staged = Self.status("1 M. N... 100644 100644 100644 aaaa bbbb a.swift")
        reader.entries[source] = Self.entries("a.swift")
        reader.workingTreeStatuses[source] = unstaged
        let sut = makeSUT()
        sut.load(source, repository: Self.info)
        try await taskProvider.waitForAllTasks()
        _ = try await reader.workingTreeStatusRequests.expectNext()

        // The reload's status read and listing are both held, so it started first and lands last.
        let statusGate = AsyncProbe<Void>()
        let listingGate = AsyncProbe<Void>()
        reader.gate["status:" + Self.gateKey(source)] = statusGate
        reader.gate[Self.gateKey(source)] = listingGate
        sut.reload()
        _ = try await reader.workingTreeStatusRequests.expectNext()
        reader.gate["status:" + Self.gateKey(source)] = nil

        // Staging lands through a refresh while the reload is still out.
        let published = AsyncProbe<Void>()
        sut.onBadgeStatesChanged = { published.send(()) }
        reader.workingTreeStatuses[source] = staged
        sut.refreshBadgeStates()
        _ = try await published.expectNext()
        #expect(sut.badgeState(of: "a.swift") == .staged)

        // The reload's read comes back with the answer from before the staging.
        reader.workingTreeStatuses[source] = unstaged
        statusGate.send(())
        listingGate.send(())
        try await taskProvider.waitForAllTasks()

        #expect(sut.badgeState(of: "a.swift") == .staged)
        #expect(sut.entries.map(\.relativePath) == ["a.swift"])
    }
}
