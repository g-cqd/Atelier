import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The model's freshness wiring over a scripted repository: which outside change reloads which side, which refreshes
/// the menus, and which costs nothing (GIT-01, PERF-03, GDV B4, S2 and S3). A synthetic watcher and a virtual clock
/// drive the watcher; the time limit bounds a reload that never comes.
@MainActor
@Suite(.mainActorLane, .timeLimit(.minutes(1)))
struct DiffViewerModelFreshnessTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
    private nonisolated static let tree = ComparisonSource.directory(root)
    private static let treeDebounce: Duration = .milliseconds(600)
    private static let refDebounce: Duration = .milliseconds(150)

    private let taskProvider = TaskProviderSpy.tolerant()
    private let clock = TestClock()
    private let reader = ScriptedGitReader()
    private let watchers = WatcherFactory()
    private let scratchDefaults = ScratchDefaults(tag: "freshness")

    private static func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    private static func info(branches: [String] = ["main"]) -> RepositoryInfo {
        RepositoryInfo(root: root, branches: branches, tags: [], commits: [])
    }

    private func makeSUT() -> DiffViewerModel {
        DiffViewerModel(
            settings: ViewerSettings(defaults: scratchDefaults.defaults), reader: reader, taskProvider: taskProvider)
    }

    /// `HEAD` at commit `c1` against its working tree, both listing `tree`, with the watcher attached.
    private func makeLoadedSUT(tree: [SourceEntry] = [entry("a.swift", "1")]) async throws
        -> (DiffViewerModel, FakeWatchEventSource)
    {
        reader.repositories[Self.root] = Self.info()
        reader.commits = ["HEAD": "c1"]
        reader.entries[Self.head] = tree
        reader.entries[Self.tree] = tree
        let sut = makeSUT()
        sut.left.load(Self.head, repository: Self.info())
        sut.right.load(Self.tree, repository: Self.info())
        try await taskProvider.waitForAllTasks()
        sut.attachFreshness(clock: clock, makeWatcher: watchers.makeWatcher)
        let source = try #require(watchers.latest)
        try await source.waitUntilWatching(2)
        return (sut, source)
    }

    /// Reports a write at `path`, lets its debounce run out, and waits until everything it started has finished.
    private func report(_ path: String, on source: FakeWatchEventSource, after debounce: Duration) async throws {
        let mark = clock.registrationMark()
        try #require(source.write(path))
        try await clock.expectSleepers(after: mark)
        clock.advance(by: debounce)
        try await taskProvider.waitForAllTasks()
    }

    private func drain(_ sut: DiffViewerModel) async throws {
        sut.freshness?.teardown()
        try await taskProvider.waitForAllTasks()
        try await taskProvider.waitForObservationsToFinish()
    }

    // MARK: Working-tree writes

    @Test
    func `a save made while a reload lists the tree still shows once that reload lands`() async throws {
        let (sut, source) = try await makeLoadedSUT(tree: [Self.entry("a.swift", "1"), Self.entry("b.swift", "1")])

        // Save A; its reload starts listing the tree, and the listing is held.
        reader.entries[Self.tree] = [Self.entry("a.swift", "2"), Self.entry("b.swift", "1")]
        let listing = reader.gateNextListing(of: Self.tree)
        let saveA = clock.registrationMark()
        try #require(source.write("/repo/a.swift"))
        try await clock.expectSleepers(after: saveA)
        clock.advance(by: Self.treeDebounce)
        _ = try await listing.reached.expectNext()

        // Save B while A's listing runs, then let A's listing land without B.
        reader.entries[Self.tree] = [Self.entry("a.swift", "2"), Self.entry("b.swift", "2")]
        let saveB = clock.registrationMark()
        try #require(source.write("/repo/b.swift"))
        try await clock.expectSleepers(after: saveB)
        listing.open()
        try await awaitObserved { !sut.right.isLoading }
        #expect(sut.right.entriesByPath["b.swift"]?.blobID == "1")
        try #require(watchers.all.count == 1)

        clock.advance(by: Self.treeDebounce)
        try await taskProvider.waitForAllTasks()

        #expect(sut.right.entriesByPath["b.swift"]?.blobID == "2")
        try await drain(sut)
    }

    @Test
    func `a write under .build-index-build reloads nothing and asks git nothing`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        let listings = reader.listings(of: Self.tree)

        try await report(
            "/repo/.build/index-build/Index/v5/records/AB/a.swift-1Q2W3E", on: source, after: Self.treeDebounce)

        #expect(reader.listings(of: Self.tree) == listings)
        #expect(reader.ignoreChecks.isEmpty)
        try await drain(sut)
    }

    @Test
    func `a write to Xcode's user state, which git ignores, reloads nothing`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        let userState = "App.xcodeproj/project.xcworkspace/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate"
        reader.ignoredPaths = [userState]
        let listings = reader.listings(of: Self.tree)

        try await report("/repo/" + userState, on: source, after: Self.treeDebounce)

        #expect(reader.listings(of: Self.tree) == listings)
        #expect(reader.ignoreChecks == [[userState]])
        try await drain(sut)
    }

    @Test
    func `an edit to a tracked dotfile reloads the working tree`() async throws {
        let (sut, source) = try await makeLoadedSUT(tree: [
            Self.entry("a.swift", "1"), Self.entry(".swiftlint.yml", "1")
        ])
        reader.entries[Self.tree] = [Self.entry("a.swift", "1"), Self.entry(".swiftlint.yml", "2")]

        try await report("/repo/.swiftlint.yml", on: source, after: Self.treeDebounce)

        #expect(sut.right.entriesByPath[".swiftlint.yml"]?.blobID == "2")
        #expect(reader.ignoreChecks.isEmpty)
        try await drain(sut)
    }

    @Test
    func `a new file git does not ignore reloads the working tree`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        reader.entries[Self.tree] = [Self.entry("a.swift", "1"), Self.entry("new.swift", "1")]

        try await report("/repo/new.swift", on: source, after: Self.treeDebounce)

        #expect(sut.right.entriesByPath["new.swift"] != nil)
        #expect(reader.ignoreChecks == [["new.swift"]])
        try await drain(sut)
    }

    @Test
    func `a new dotfile git does not ignore reloads the working tree`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        reader.entries[Self.tree] = [Self.entry("a.swift", "1"), Self.entry(".github/workflows/ci.yml", "1")]

        try await report("/repo/.github/workflows/ci.yml", on: source, after: Self.treeDebounce)

        #expect(sut.right.entriesByPath[".github/workflows/ci.yml"] != nil)
        #expect(reader.ignoreChecks == [[".github/workflows/ci.yml"]])
        try await drain(sut)
    }

    // MARK: Refs and HEAD

    @Test
    func `a refs change that leaves every commit in place reloads nothing and refreshes both menus`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        let listings = (reader.listings(of: Self.head), reader.listings(of: Self.tree))
        reader.repositories[Self.root] = Self.info(branches: ["main", "origin/main"])

        // A fetch by another tool moves a remote-tracking branch, not the checked-out one.
        try await report("/repo/.git/refs/remotes/origin/main", on: source, after: Self.refDebounce)

        #expect(reader.listings(of: Self.head) == listings.0)
        #expect(reader.listings(of: Self.tree) == listings.1)
        #expect(sut.left.repository?.branches == ["main", "origin/main"])
        #expect(sut.right.repository?.branches == ["main", "origin/main"])
        #expect(reader.repositoryInfoReads == 1)
        try await drain(sut)
    }

    @Test
    func `a comparison opened on HEAD knows the commit it listed, so a refs change that keeps it reloads nothing`()
        async throws
    {
        reader.repositories[Self.root] = Self.info()
        reader.commits = ["HEAD": "c1"]
        reader.entries[Self.head] = [Self.entry("a.swift", "1")]
        reader.entries[Self.tree] = [Self.entry("a.swift", "2")]
        let sut = makeSUT()
        sut.compareGitChanges(in: Self.root)
        try await taskProvider.waitForAllTasks()
        sut.attachFreshness(clock: clock, makeWatcher: watchers.makeWatcher)
        let source = try #require(watchers.latest)
        try await source.waitUntilWatching(2)
        let listings = reader.listings(of: Self.head)

        try await report("/repo/.git/refs/remotes/origin/main", on: source, after: Self.refDebounce)

        #expect(sut.left.resolvedCommit == "c1")
        #expect(reader.listings(of: Self.head) == listings)
        try await drain(sut)
    }

    @Test
    func `a commit on the checked-out branch reloads the HEAD side alone`() async throws {
        let (sut, source) = try await makeLoadedSUT()
        let treeListings = reader.listings(of: Self.tree)
        reader.commits = ["HEAD": "c2"]
        reader.entries[Self.head] = [Self.entry("a.swift", "2")]

        try await report("/repo/.git/refs/heads/main", on: source, after: Self.refDebounce)

        #expect(sut.left.entriesByPath["a.swift"]?.blobID == "2")
        #expect(sut.left.resolvedCommit == "c2")
        #expect(reader.listings(of: Self.tree) == treeListings)
        try await drain(sut)
    }

    @Test
    func `a checkout that moves HEAD reloads the HEAD side, and one that keeps its commit reloads nothing`()
        async throws
    {
        let (sut, source) = try await makeLoadedSUT()
        reader.commits = ["HEAD": "c2"]
        reader.entries[Self.head] = [Self.entry("a.swift", "2")]

        try await report("/repo/.git/HEAD", on: source, after: Self.refDebounce)
        #expect(sut.left.entriesByPath["a.swift"]?.blobID == "2")
        let listings = reader.listings(of: Self.head)

        // `git checkout -b feature` points HEAD at a new branch on the same commit.
        try await report("/repo/.git/HEAD", on: source, after: Self.refDebounce)

        #expect(reader.listings(of: Self.head) == listings)
        try await drain(sut)
    }

    @Test
    func `in a linked worktree, a commit reloads the HEAD side and staging refreshes the badges alone`() async throws {
        let worktree = try LinkedWorktree()
        defer { worktree.remove() }
        let root = worktree.rootURL
        let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
        let tree = ComparisonSource.directory(root)
        let info = RepositoryInfo(root: root, branches: ["feature"], tags: [], commits: [])
        reader.repositories[root] = info
        reader.commits = ["HEAD": "c1"]
        reader.entries[head] = [Self.entry("a.swift", "1")]
        reader.entries[tree] = [Self.entry("a.swift", "1")]
        let sut = makeSUT()
        sut.left.load(head, repository: info)
        sut.right.load(tree, repository: info)
        try await taskProvider.waitForAllTasks()
        sut.attachFreshness(clock: clock, makeWatcher: watchers.makeWatcher)
        let source = try #require(watchers.latest)
        try await source.waitUntilWatching(3)
        let treeListings = reader.listings(of: tree)

        reader.commits = ["HEAD": "c2"]
        reader.entries[head] = [Self.entry("a.swift", "2")]
        try await report(worktree.commonGitDir + "/refs/heads/feature", on: source, after: Self.refDebounce)
        #expect(sut.left.entriesByPath["a.swift"]?.blobID == "2")

        reader.statuses[tree] =
            GitParsers.porcelainV2(
                Data("1 M. N... 100644 100644 100644 aaaa bbbb a.swift\u{0}".utf8)
            )
            .entries
        try await report(worktree.privateGitDir + "/index", on: source, after: Self.refDebounce)

        #expect(sut.right.badgeState(of: "a.swift") == .staged)
        #expect(reader.listings(of: tree) == treeListings)
        try await drain(sut)
    }
}
