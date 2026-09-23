import AemiTesting
import AtelierFileTree
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// When ``RepositoryFreshness`` attaches, to which directories, and what keeps the attachment: the same comparison
/// keeps its stream and its pending debounces across reloads (GDV B4), while a disabled watcher, a teardown or a moved
/// git dir attaches afresh. Linked worktrees and symlinked folders are watched where FSEvents reports them (GDV B5).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepositoryFreshnessAttachmentTests {
    private let harness = WatcherHarness()

    @Test
    func `attaching watches the tree and its git dir through one stream, and no file on its own`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")

        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)
        try await source.waitUntilWatching(2)

        #expect(source.watchedDirectories == ["/repo", "/repo/.git"])
        try await harness.drain(sut)
    }

    @Test
    func `attaching to a linked worktree watches its root, its own git dir and the git dir every worktree shares`()
        async throws
    {
        let worktree = try LinkedWorktree()
        defer { worktree.remove() }
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)

        sut.comparisonChanged(rightSource: .directory(worktree.rootURL), repositoryRoot: worktree.rootURL)
        let source = try #require(factory.latest)
        try await source.waitUntilWatching(3)

        #expect(source.watchedDirectories == [worktree.root, worktree.privateGitDir, worktree.commonGitDir])
        try await harness.drain(sut)
    }

    @Test
    func `in a linked worktree, a commit on its branch fires onRefsChanged and staging fires onIndexChanged`()
        async throws
    {
        let worktree = try LinkedWorktree()
        defer { worktree.remove() }
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let refs = AsyncProbe<Void>()
        let index = AsyncProbe<Void>()
        sut.onRefsChanged = { refs.send(()) }
        sut.onIndexChanged = { index.send(()) }
        sut.comparisonChanged(rightSource: .directory(worktree.rootURL), repositoryRoot: worktree.rootURL)
        let source = try #require(factory.latest)
        try await source.waitUntilWatching(3)

        try await harness.write(
            worktree.commonGitDir + "/refs/heads/feature", on: source, after: WatcherHarness.refDebounce, probe: refs)
        try await harness.write(
            worktree.privateGitDir + "/index", on: source, after: WatcherHarness.refDebounce, probe: index)

        try refs.expectNoBufferedElements()
        try index.expectNoBufferedElements()
        try await harness.drain(sut)
    }

    @Test
    func `a tree whose folder the caller names through a symlink reports under its real path`() async throws {
        let worktree = try LinkedWorktree()
        defer { worktree.remove() }
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        // The temporary directory lies under `/var`, a symlink to `/private/var`, which is what FSEvents reports.
        #expect(worktree.root != worktree.rootURL.path(percentEncoded: false))

        sut.comparisonChanged(rightSource: .directory(worktree.rootURL), repositoryRoot: worktree.rootURL)
        let source = try #require(factory.latest)
        try await source.waitUntilWatching(3)

        try await harness.write(
            worktree.root + "/a.swift", on: source, after: WatcherHarness.treeDebounce, probe: probe)
        try await harness.drain(sut)
    }

    @Test
    func `a second and a third checkout each fire onHeadChanged`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        sut.onHeadChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)
        try await source.waitUntilWatching(2)

        for _ in 1 ... 3 {
            // Git renames a new HEAD over the old one, and the reload each checkout causes reports the same comparison.
            try await harness.write("/repo/.git/HEAD", on: source, after: WatcherHarness.refDebounce, probe: probe)
            sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
            try #require(factory.all.count == 1)
        }

        try probe.expectNoBufferedElements()
        try await harness.drain(sut)
    }

    @Test
    func `nothing attaches when the right side is not the repository's own working tree`() {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")

        sut.comparisonChanged(rightSource: .directory(WatcherHarness.url("/elsewhere")), repositoryRoot: root)
        #expect(factory.latest == nil)

        sut.comparisonChanged(rightSource: .gitRef(repository: root, ref: "main"), repositoryRoot: root)
        #expect(factory.latest == nil)

        sut.comparisonChanged(rightSource: nil, repositoryRoot: nil)
        #expect(factory.latest == nil)
    }

    @Test
    func `the same comparison reported again keeps the watcher and the reload it has pending`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        // A save lands while a reload lists the tree; the reload then reports the same comparison.
        let mark = harness.clock.registrationMark()
        source.send(.directoryChanged("/repo/b.swift"))
        try await harness.clock.expectSleepers(after: mark)
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        try #require(factory.all.count == 1)
        harness.clock.advance(by: WatcherHarness.treeDebounce)

        _ = try await probe.expectNext()
        #expect(!source.isStopped)
        try await harness.drain(sut)
    }

    @Test
    func `a git dir that moved attaches afresh to where it now lies`() async throws {
        let worktree = try LinkedWorktree()
        defer { worktree.remove() }
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        sut.comparisonChanged(rightSource: .directory(worktree.rootURL), repositoryRoot: worktree.rootURL)
        let first = try #require(factory.latest)

        let moved = try worktree.movePrivateGitDir(to: "renamed")
        sut.comparisonChanged(rightSource: .directory(worktree.rootURL), repositoryRoot: worktree.rootURL)

        let second = try #require(factory.all.dropFirst().first)
        try await second.waitUntilWatching(3)
        #expect(second.watchedDirectories.contains(moved))
        try await harness.taskProvider.waitForAllTasks()
        #expect(first.isStopped)
        try await harness.drain(sut)
    }

    @Test
    func `events from a torn-down watcher never reach a later comparison's callbacks`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onTreeChanged = {
            treeChanges += 1
            probe.send(())
        }

        let repositoryA = WatcherHarness.url("/repoA")
        sut.comparisonChanged(rightSource: .directory(repositoryA), repositoryRoot: repositoryA)
        let staleSource = try #require(factory.latest)

        let repositoryB = WatcherHarness.url("/repoB")
        sut.comparisonChanged(rightSource: .directory(repositoryB), repositoryRoot: repositoryB)
        let freshSource = try #require(factory.all.dropFirst().first)

        // The stale event is dropped; a fresh one proves the pipeline moved on and settles the count.
        staleSource.send(.directoryChanged("/repoA/a.swift"))
        try await harness.fire(
            .directoryChanged("/repoB/b.swift"), on: freshSource, after: WatcherHarness.treeDebounce, probe: probe)

        #expect(treeChanges == 1)
        try await harness.drain(sut)
    }

    @Test
    func `disabling autoRefresh stops the watcher and enabling it reattaches`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(isEnabled: true, factory: factory)
        let root = WatcherHarness.url("/repo")
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let first = try #require(factory.latest)

        sut.setEnabled(false)
        try await harness.taskProvider.waitForAllTasks()
        #expect(first.isStopped)

        sut.setEnabled(true)
        let second = try #require(factory.all.dropFirst().first)
        #expect(second !== first)

        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        try await harness.fire(
            .directoryChanged("/repo/a.swift"), on: second, after: WatcherHarness.treeDebounce, probe: probe)
        try await harness.drain(sut)
    }

    @Test
    func `a teardown forgets the attachment, so the same comparison attaches again`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)

        sut.teardown()
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)

        #expect(factory.all.count == 2)
        try await harness.drain(sut)
    }

    @Test
    func `a comparison built with autoRefresh already off never attaches`() {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(isEnabled: false, factory: factory)
        let root = WatcherHarness.url("/repo")

        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)

        #expect(factory.latest == nil)
    }
}
