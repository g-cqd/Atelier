import AemiTesting
import AtelierFileTree
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// How ``RepositoryFreshness`` routes what the watcher reports: each kind of change to its callback on a trailing
/// debounce, and the tree's writes through the filter that judges whether a reload can show them. A synthetic
/// ``WatchEventSource`` and a virtual clock drive it; the time limit bounds a callback that never comes.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepositoryFreshnessTests {
    private let harness = WatcherHarness()

    @Test
    func `a burst of tree events coalesces into one reload after the trailing debounce`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onTreeChanged = {
            treeChanges += 1
            probe.send(())
        }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        source.send(.directoryChanged("/repo/a.swift"))
        try await harness.clock.waitForSleepers()
        harness.clock.advance(by: .milliseconds(300))
        #expect(treeChanges == 0)

        // Waits for a fresh sleeper registration, since the cancelled one may still be queued.
        let mark = harness.clock.registrationMark()
        source.send(.directoryChanged("/repo/b.swift"))
        try await harness.clock.waitForSleepers(1, after: mark)
        harness.clock.advance(by: WatcherHarness.treeDebounce)
        _ = try await probe.next()

        #expect(treeChanges == 1)
        try await harness.drain(sut)
    }

    @Test
    func `a HEAD change fires onHeadChanged, not onTreeChanged`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onHeadChanged = { probe.send(()) }
        sut.onTreeChanged = { treeChanges += 1 }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await harness.fire(
            .directoryChanged("/repo/.git/HEAD"), on: source, after: WatcherHarness.refDebounce, probe: probe)

        #expect(treeChanges == 0)
        try await harness.drain(sut)
    }

    @Test
    func `staging, which renames a new index over the old one, fires onIndexChanged and nothing else`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        var otherChanges = 0
        sut.onIndexChanged = { probe.send(()) }
        sut.onTreeChanged = { otherChanges += 1 }
        sut.onHeadChanged = { otherChanges += 1 }
        sut.onRefsChanged = { otherChanges += 1 }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        source.send(.directoryChanged("/repo/.git/index.lock"))
        try await harness.fire(
            .directoryChanged("/repo/.git/index"), on: source, after: WatcherHarness.refDebounce, probe: probe)

        #expect(otherChanges == 0)
        try await harness.drain(sut)
    }

    @Test
    func `a ref change fires onRefsChanged, packed or loose`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let probe = AsyncProbe<Void>()
        sut.onRefsChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await harness.fire(
            .directoryChanged("/repo/.git/refs/remotes/origin/main"), on: source, after: WatcherHarness.refDebounce,
            probe: probe)
        try await harness.fire(
            .directoryChanged("/repo/.git/packed-refs"), on: source, after: WatcherHarness.refDebounce, probe: probe)
        try await harness.drain(sut)
    }

    @Test
    func `a rescan of the root reloads without asking the filter and re-reads HEAD, the refs and the index`()
        async throws
    {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let tree = AsyncProbe<Void>()
        let metadata = CountProbe<String>()
        var filterCalls = 0
        sut.treeChangeFilter = { _ in
            filterCalls += 1
            return false
        }
        sut.onTreeChanged = { tree.send(()) }
        sut.onHeadChanged = { metadata.record("head") }
        sut.onRefsChanged = { metadata.record("refs") }
        sut.onIndexChanged = { metadata.record("index") }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        source.send(.directoryChanged("/repo"))
        try await harness.clock.waitForSleepers(count: 4)
        harness.clock.advance(by: WatcherHarness.treeDebounce)
        _ = try await tree.next()
        try await metadata.wait(forAtLeast: 3, timeout: TaskProviderSpy.failureBound)

        #expect(Set(metadata.events) == ["head", "refs", "index"])
        #expect(filterCalls == 0)
        try await harness.drain(sut)
    }

    @Test
    func `a path under a skipped directory never reaches the tree filter`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let judged = AsyncProbe<Set<String>>()
        sut.treeChangeFilter = { paths in
            judged.send(paths)
            return true
        }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        // The skipped path schedules nothing; the legitimate one after it proves the pipeline is live.
        source.send(.directoryChanged("/repo/node_modules/left-pad/index.js"))
        source.send(.directoryChanged("/repo/Sources/Foo.swift"))
        try await harness.clock.waitForSleepers()
        harness.clock.advance(by: WatcherHarness.treeDebounce)

        #expect(try await judged.next() == ["Sources/Foo.swift"])
        try await harness.drain(sut)
    }

    @Test
    func `the filter gets the written paths relative to the root, and a filter that finds none reloads nothing`()
        async throws
    {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let judged = AsyncProbe<Set<String>>()
        var treeChanges = 0
        sut.treeChangeFilter = { paths in
            judged.send(paths)
            return false
        }
        sut.onTreeChanged = { treeChanges += 1 }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        source.send(.directoryChanged("/repo/build/out.o"))
        try await harness.clock.waitForSleepers()
        let mark = harness.clock.registrationMark()
        source.send(.directoryChanged("/repo/App.xcodeproj/xcuserdata/UserInterfaceState.xcuserstate"))
        try await harness.clock.waitForSleepers(1, after: mark)
        harness.clock.advance(by: WatcherHarness.treeDebounce)

        #expect(
            try await judged.next() == ["build/out.o", "App.xcodeproj/xcuserdata/UserInterfaceState.xcuserstate"])
        try await harness.taskProvider.waitForAllTasks()
        #expect(treeChanges == 0)
        try await harness.drain(sut)
    }

    @Test
    func `a write arriving while the filter runs hands every path to the next check`() async throws {
        let factory = WatcherFactory()
        let sut = harness.makeSUT(factory: factory)
        let root = WatcherHarness.url("/repo")
        let judged = AsyncProbe<Set<String>>()
        let neverAnswered = AsyncProbe<Bool>()
        var checks = 0
        let reloads = AsyncProbe<Void>()
        sut.treeChangeFilter = { paths in
            checks += 1
            judged.send(paths)
            guard checks == 1 else { return true }
            // The first check waits until the next write cancels it.
            return (try? await neverAnswered.next()) ?? false
        }
        sut.onTreeChanged = { reloads.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)
        source.send(.directoryChanged("/repo/a.swift"))
        try await harness.clock.waitForSleepers()
        harness.clock.advance(by: WatcherHarness.treeDebounce)
        #expect(try await judged.next() == ["a.swift"])

        // The second write lands while the first check waits on its verdict, and supersedes it.
        let mark = harness.clock.registrationMark()
        source.send(.directoryChanged("/repo/b.swift"))
        try await harness.clock.waitForSleepers(1, after: mark)
        harness.clock.advance(by: WatcherHarness.treeDebounce)

        #expect(try await judged.next() == ["a.swift", "b.swift"])
        _ = try await reloads.next()
        try await harness.taskProvider.waitForAllTasks()
        try reloads.expectNoBufferedElements()
        try await harness.drain(sut)
    }
}
