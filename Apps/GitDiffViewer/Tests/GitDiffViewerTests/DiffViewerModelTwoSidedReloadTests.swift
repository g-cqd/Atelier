import AemiCore
import AemiTesting
import AtelierFileTree
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A reload of both sides keeps the comparison on screen while they land one after the other: the first side to land
/// always finds the other still loading, and must not collapse what is published (book GIT-03, GIT-04).
@MainActor
struct DiffViewerModelTwoSidedReloadTests {
    private let harness = ModelTestHarness()

    /// Loads two changed files on each side, the right side a folder whose listing the test can hold.
    private func loadTwoChangedFiles(_ sut: DiffViewerModel) async throws {
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
    }

    /// A probe that fires each time `side` lands a listing, after the model has taken it.
    private func landings(of side: SideState) -> AsyncProbe<Void> {
        let probe = AsyncProbe<Void>()
        let modelHandler = side.onEntriesChanged
        side.onEntriesChanged = {
            modelHandler?()
            probe.send(())
        }
        return probe
    }

    @Test
    func `the Reload button keeps the comparison and the cards on screen while the second side is still loading`()
        async throws
    {
        let sut = harness.makeSUT()
        try await loadTwoChangedFiles(sut)
        let cardsBefore = sut.renderedFiles.map(\.rendered.id)
        let leftLandings = landings(of: sut.left)
        let rightListing = harness.holdListing(of: ModelTestHarness.rightURL)

        sut.reloadSources()
        _ = try await leftLandings.next()

        #expect(sut.right.isLoading)
        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.rendered.id) == cardsBefore)
        #expect(sut.statuses["a.swift"] == .different)
        #expect(sut.leftTree.map(\.id) == ["a.swift", "b.swift"])

        rightListing.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a two-sided reload that changes no file keeps every card's identity`() async throws {
        let sut = harness.makeSUT()
        try await loadTwoChangedFiles(sut)
        let cardsBefore = sut.renderedFiles.map(\.rendered.id)

        sut.reloadSources()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.map(\.rendered.id) == cardsBefore)
    }

    @Test
    func `a refs change while parked on HEAD keeps the cards on screen while the working tree reloads`() async throws {
        let sut = harness.makeSUT()
        let root = ModelTestHarness.rightURL
        let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
        let repository = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
        harness.reader.commits = ["HEAD": "c1"]
        harness.reader.entries[head] = [harness.entry("a.swift", "1"), harness.entry("b.swift", "2")]
        harness.reader.entries[.directory(root)] = [harness.entry("a.swift", "3"), harness.entry("b.swift", "4")]
        sut.attachFreshness(clock: harness.clock, makeWatcher: WatcherFactory().makeWatcher)
        sut.left.load(head, repository: repository)
        sut.right.load(.directory(root), repository: repository)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
        let leftLandings = landings(of: sut.left)
        let rightListing = harness.holdListing(of: root)

        // A checkout rewrites the working tree, whose reload is held, and moves HEAD to another commit: the refs
        // change reloads the HEAD side, which lands first.
        sut.freshness?.onTreeChanged?()
        harness.reader.commits = ["HEAD": "c2"]
        harness.reader.entries[head] = [harness.entry("a.swift", "5"), harness.entry("b.swift", "2")]
        sut.freshness?.onRefsChanged?()
        _ = try await leftLandings.next()

        #expect(sut.right.isLoading)
        #expect(sut.detailState == .cards)
        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "b.swift"])

        rightListing.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
        sut.freshness?.teardown()
        try await harness.taskProvider.waitForAllTasks()
        try await harness.taskProvider.waitForObservationsToFinish()
    }
}
