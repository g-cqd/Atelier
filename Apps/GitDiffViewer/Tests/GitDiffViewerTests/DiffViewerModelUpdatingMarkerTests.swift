import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// What the detail area showed at each publish: the cards' render identities, and how they related to what the
/// window asked for.
@MainActor
final class PublishLog {
    var entries: [(cards: [RenderedDiff.ID], shown: ShownComparison)] = []

    /// Starts recording `sut`'s publishes, each after the model handled it.
    init(_ sut: DiffViewerModel) {
        let modelHandler = sut.pipeline.onEvent
        sut.pipeline.onEvent = { [weak self, weak sut] event in
            modelHandler?(event)
            guard case .published = event, let sut else { return }
            self?.entries.append((sut.renderedFiles.map(\.rendered.id), sut.shownComparison))
        }
    }
}

/// Swap, another ref and another folder keep the previous cards on screen, marked as updating, until the new
/// comparison replaces them in one step; a load that fails keeps them marked with the failure (book D13, GIT-03).
@MainActor
struct DiffViewerModelUpdatingMarkerTests {
    private let harness = ModelTestHarness()
    private static let root = ModelTestHarness.rightURL
    private static let main = ComparisonSource.gitRef(repository: root, ref: "main")
    private static let feature = ComparisonSource.gitRef(repository: root, ref: "feature")
    private static let repository = RepositoryInfo(root: root, branches: ["main", "feature"], tags: [], commits: [])

    /// Loads two changed files, left against right, and drains the four reads they made.
    private func loadFolders(_ sut: DiffViewerModel) async throws {
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }
    }

    /// Loads `main` against the working tree, two changed files, and drains the four reads they made.
    private func loadMainAgainstWorkingTree(_ sut: DiffViewerModel) async throws {
        harness.reader.entries[Self.main] = [harness.entry("a.swift", "1"), harness.entry("b.swift", "2")]
        harness.reader.entries[Self.feature] = [harness.entry("a.swift", "5"), harness.entry("b.swift", "6")]
        harness.reader.entries[.directory(Self.root)] = [harness.entry("a.swift", "3"), harness.entry("b.swift", "4")]
        sut.left.load(Self.main, repository: Self.repository)
        sut.right.load(.directory(Self.root), repository: Self.repository)
        try await harness.taskProvider.waitForAllTasks()
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }
    }

    @Test
    func `swapping sides keeps the previous cards marked until the swapped comparison replaces them in one step`()
        async throws
    {
        let sut = harness.makeSUT()
        try await loadFolders(sut)
        let previous = sut.renderedFiles.map(\.rendered.id)
        let log = PublishLog(sut)
        harness.reader.gate["a.swift"] = AsyncProbe<Void>()

        sut.swapSides()
        #expect(sut.shownComparison == .previous)
        _ = try await harness.reader.contentRequests.next()
        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.rendered.id) == previous)
        #expect(sut.shownComparison == .previous)

        harness.reader.gate["a.swift"]?.send(())
        harness.reader.gate["a.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.shown == .current)
        #expect(log.entries.first?.cards == sut.renderedFiles.map(\.rendered.id))
        #expect(Set(sut.renderedFiles.map(\.rendered.id)).isDisjoint(with: previous))
    }

    @Test
    func `another ref keeps the previous cards marked until the new comparison replaces them in one step`()
        async throws
    {
        let sut = harness.makeSUT()
        try await loadMainAgainstWorkingTree(sut)
        let previous = sut.renderedFiles.map(\.rendered.id)
        let log = PublishLog(sut)
        harness.reader.gate["a.swift"] = AsyncProbe<Void>()

        sut.left.refChoice = .ref("feature")
        #expect(sut.shownComparison == .previous)
        _ = try await harness.reader.contentRequests.next()
        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.rendered.id) == previous)
        #expect(sut.shownComparison == .previous)

        harness.reader.gate["a.swift"]?.send(())
        harness.reader.gate["a.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(log.entries.count == 1)
        #expect(log.entries.first?.shown == .current)
        #expect(sut.shownComparison == .current)
    }

    @Test
    func `a reload of the same sources leaves the cards unmarked`() async throws {
        let sut = harness.makeSUT()
        try await loadFolders(sut)
        let rightListing = harness.holdListing(of: ModelTestHarness.rightURL)

        sut.reloadSources()
        #expect(sut.shownComparison == .current)
        rightListing.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.shownComparison == .current)
    }

    @Test
    func `a ref whose files cannot be listed keeps the previous cards marked with the failure`() async throws {
        let sut = harness.makeSUT()
        try await loadMainAgainstWorkingTree(sut)
        let previous = sut.renderedFiles.map(\.rendered.id)
        harness.reader.failingListings[Self.feature] = "fatal: not a tree object"

        sut.left.refChoice = .ref("feature")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.rendered.id) == previous)
        #expect(sut.shownComparison == .previousAfterFailure("fatal: not a tree object"))
    }

    @Test
    func `a failed ref leaves nothing marked once the side is back on a ref that loads`() async throws {
        let sut = harness.makeSUT()
        try await loadMainAgainstWorkingTree(sut)
        let previous = sut.renderedFiles.map(\.rendered.id)
        harness.reader.failingListings[Self.feature] = "fatal: not a tree object"
        sut.left.refChoice = .ref("feature")
        try await harness.taskProvider.waitForAllTasks()

        sut.left.refChoice = .ref("main")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.shownComparison == .current)
        #expect(sut.renderedFiles.map(\.rendered.id) == previous)
    }

    @Test
    func `a file that cannot be read keeps the previous cards marked with the failure`() async throws {
        let sut = harness.makeSUT()
        try await loadFolders(sut)
        let previous = sut.renderedFiles.map(\.rendered.id)
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "9")
        ]
        harness.reader.failingContents["b.swift"] = "Permission denied"

        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.rendered.id) == previous)
        #expect(sut.shownComparison == .previousAfterFailure("Permission denied"))
    }

    @Test
    func `a repository that cannot be opened keeps the previous cards marked with the failure`() async throws {
        let sut = harness.makeSUT()
        try await loadFolders(sut)

        sut.compareGitChanges(in: URL(filePath: "/nowhere", directoryHint: .isDirectory))
        #expect(sut.shownComparison == .previous)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.detailState == .cards)
        #expect(sut.shownComparison == .previousAfterFailure("/nowhere is not inside a git repository."))
    }

    @Test
    func `a selection made while a side reloads marks the cards until the selected file lands`() async throws {
        let sut = harness.makeSUT()
        try await loadFolders(sut)
        let rightListing = harness.holdListing(of: ModelTestHarness.rightURL)
        sut.right.reload()

        sut.select("a.swift")
        #expect(sut.detailState == .cards)
        #expect(sut.shownComparison == .previous)
        rightListing.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.shownComparison == .current)
        if case .file = sut.detailState {} else { Issue.record("expected the selected file, got \(sut.detailState)") }
    }
}
