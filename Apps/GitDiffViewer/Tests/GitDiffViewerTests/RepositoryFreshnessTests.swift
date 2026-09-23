import AemiTesting
import AtelierFileTree
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// Classification, debounce coalescing and teardown of ``RepositoryFreshness``, against a synthetic
/// ``WatchEventSource`` and a virtual clock.
@MainActor
struct RepositoryFreshnessTests {
    private let taskProvider = TaskProviderSpy.tolerant()
    private let clock = TestClock()

    // MARK: Classification (pure, no watcher needed)

    private static let root = "/repo"
    private static let gitDir = "/repo/.git"
    private static let head = "/repo/.git/HEAD"
    private static let packedRefs = "/repo/.git/packed-refs"
    private static let refs = "/repo/.git/refs"

    private func classify(_ path: String) -> RepositoryFreshness.Classification {
        RepositoryFreshness.classify(
            path,
            paths: .init(
                root: Self.root, gitDir: Self.gitDir, head: Self.head, packedRefs: Self.packedRefs, refs: Self.refs))
    }

    @Test
    func `classify tags .git-HEAD as head`() {
        #expect(classify("/repo/.git/HEAD") == .head)
    }

    @Test
    func `classify tags packed-refs as refs`() {
        #expect(classify("/repo/.git/packed-refs") == .refs)
    }

    @Test
    func `classify tags a loose ref under refs as refs`() {
        #expect(classify("/repo/.git/refs/heads/main") == .refs)
        #expect(classify("/repo/.git/refs/remotes/origin/main") == .refs)
    }

    @Test
    func `classify tags other .git paths as ignored`() {
        #expect(classify("/repo/.git/index.lock") == .ignored)
        #expect(classify("/repo/.git/COMMIT_EDITMSG") == .ignored)
    }

    @Test
    func `classify tags the index and the git dir holding it as index`() {
        #expect(classify("/repo/.git/index") == .index)
        #expect(classify("/repo/.git") == .index)
    }

    @Test
    func `classify tags an ordinary tree file as tree`() {
        #expect(classify("/repo/Sources/Foo.swift") == .tree)
    }

    @Test
    func `classify tags a path under a skipped directory as ignored`() {
        #expect(classify("/repo/node_modules/left-pad/index.js") == .ignored)
        #expect(classify("/repo/Sources/DerivedData/Foo.swift") == .ignored)
    }

    @Test
    func `classify tags a path outside the tree as ignored`() {
        #expect(classify("/somewhere/else.swift") == .ignored)
    }

    // MARK: Wiring, debounce, teardown

    private static let treeDebounce: Duration = .milliseconds(600)
    private static let refDebounce: Duration = .milliseconds(150)

    private func makeSUT(isEnabled: Bool = true, factory: WatcherFactory = WatcherFactory()) -> RepositoryFreshness {
        RepositoryFreshness(
            taskProvider: taskProvider, isEnabled: isEnabled, clock: clock, treeDebounce: Self.treeDebounce,
            refDebounce: Self.refDebounce, makeWatcher: factory.makeWatcher)
    }

    private static func url(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Sends `event`, waits for its debounce to sleep on `clock`, advances past `duration`, then waits for `probe`.
    private func fire(
        _ event: FileWatcher.FileWatchEvent, on source: FakeWatchEventSource, after duration: Duration,
        probe: AsyncProbe<Void>
    ) async throws {
        source.send(event)
        try await clock.waitForSleepers()
        clock.advance(by: duration)
        _ = try await probe.next()
    }

    /// Stops `sut`'s watcher and drains every task behind it: tasks left to unwind on their own pile up across the
    /// suite and starve the cooperative pool.
    private func drain(_ sut: RepositoryFreshness) async throws {
        sut.teardown()
        try await taskProvider.waitForAllTasks()
        try await taskProvider.waitForObservationsToFinish()
    }

    @Test
    func `attaching watches the tree root plus HEAD, packed-refs, refs and the git dir`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)

        let source = try #require(factory.latest)
        // Watches register asynchronously; a fired callback proves every `watch*` call already ran.
        try await fire(.fileChanged("/repo/a.swift"), on: source, after: Self.treeDebounce, probe: probe)

        #expect(await source.watchedDirectories.contains("/repo"))
        #expect(await source.watchedDirectories.contains("/repo/.git/refs"))
        #expect(await source.watchedFiles.contains("/repo/.git/HEAD"))
        #expect(await source.watchedFiles.contains("/repo/.git/packed-refs"))
        #expect(await source.watchedFiles.contains("/repo/.git"))
        try await drain(sut)
    }

    @Test
    func `attaching to a linked worktree watches its private HEAD and git dir and the common refs, not <root>-.git`()
        async throws
    {
        func noTrailingSlash(_ path: String) -> String { path.hasSuffix("/") ? String(path.dropLast()) : path }
        let base = FileManager.default.temporaryDirectory
            .appending(path: "freshness-worktree-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let worktreeRoot = noTrailingSlash(
            base.appending(path: "worktree", directoryHint: .isDirectory).path(percentEncoded: false))
        let commonGitDir = noTrailingSlash(
            base.appending(path: "main/.git", directoryHint: .isDirectory).path(percentEncoded: false))
        let privateGitDir = noTrailingSlash(
            base.appending(path: "main/.git/worktrees/feature", directoryHint: .isDirectory)
                .path(percentEncoded: false))
        try FileManager.default.createDirectory(atPath: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: privateGitDir, withIntermediateDirectories: true)
        try "gitdir: \(privateGitDir)\n"
            .write(
                toFile: worktreeRoot + "/.git", atomically: true, encoding: .utf8)
        try "\(commonGitDir)\n"
            .write(
                toFile: privateGitDir + "/commondir", atomically: true, encoding: .utf8)

        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url(worktreeRoot)
        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await fire(.fileChanged(worktreeRoot + "/a.swift"), on: source, after: Self.treeDebounce, probe: probe)

        #expect(await source.watchedDirectories.contains(worktreeRoot))
        #expect(await source.watchedFiles.contains(privateGitDir + "/HEAD"))
        #expect(await source.watchedFiles.contains(privateGitDir))
        #expect(await source.watchedFiles.contains(commonGitDir + "/packed-refs"))
        #expect(await source.watchedDirectories.contains(commonGitDir + "/refs"))
        // Not the plain-repository paths, which a linked worktree's HEAD and refs never touch.
        #expect(await !source.watchedFiles.contains(worktreeRoot + "/.git/HEAD"))
        #expect(await !source.watchedDirectories.contains(worktreeRoot + "/.git/refs"))
        try await drain(sut)
    }

    @Test
    func `nothing attaches when the right side is not the repository's own working tree`() {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")

        sut.comparisonChanged(rightSource: .directory(Self.url("/elsewhere")), repositoryRoot: root)
        #expect(factory.latest == nil)

        sut.comparisonChanged(rightSource: .gitRef(repository: root, ref: "main"), repositoryRoot: root)
        #expect(factory.latest == nil)

        sut.comparisonChanged(rightSource: nil, repositoryRoot: nil)
        #expect(factory.latest == nil)
    }

    @Test
    func `a burst of tree events coalesces into one reload after the trailing debounce`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onTreeChanged = {
            treeChanges += 1
            probe.send(())
        }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        source.send(.fileChanged("/repo/a.swift"))
        try await clock.waitForSleepers()
        clock.advance(by: .milliseconds(300))
        #expect(treeChanges == 0)

        // Waits for a fresh sleeper registration, since the cancelled one may still be queued.
        let mark = clock.registrationMark()
        source.send(.fileChanged("/repo/b.swift"))
        try await clock.waitForSleepers(1, after: mark)
        clock.advance(by: Self.treeDebounce)
        _ = try await probe.next()

        #expect(treeChanges == 1)
        try await drain(sut)
    }

    @Test
    func `a HEAD change fires onHeadChanged, not onTreeChanged`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onHeadChanged = { probe.send(()) }
        sut.onTreeChanged = { treeChanges += 1 }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await fire(.fileChanged("/repo/.git/HEAD"), on: source, after: Self.refDebounce, probe: probe)

        #expect(treeChanges == 0)
        try await drain(sut)
    }

    @Test
    func `staging, reported on the git dir, fires onIndexChanged and neither a reload nor a re-comparison`()
        async throws
    {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        var otherChanges = 0
        sut.onIndexChanged = { probe.send(()) }
        sut.onTreeChanged = { otherChanges += 1 }
        sut.onHeadChanged = { otherChanges += 1 }
        sut.onRefsChanged = { otherChanges += 1 }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await fire(.fileChanged("/repo/.git"), on: source, after: Self.refDebounce, probe: probe)

        #expect(otherChanges == 0)
        try await drain(sut)
    }

    @Test
    func `a ref change fires onRefsChanged, packed or loose`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        sut.onRefsChanged = { probe.send(()) }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        try await fire(
            .fileChanged("/repo/.git/refs/remotes/origin/main"), on: source, after: Self.refDebounce, probe: probe)
        try await drain(sut)
    }

    @Test
    func `a skipped directory never reaches the tree callback`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let root = Self.url("/repo")
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onTreeChanged = {
            treeChanges += 1
            probe.send(())
        }
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let source = try #require(factory.latest)

        // A legitimate event after the skipped one proves the pipeline is live and only it reloaded.
        source.send(.fileChanged("/repo/node_modules/left-pad/index.js"))
        try await fire(.fileChanged("/repo/Sources/Foo.swift"), on: source, after: Self.treeDebounce, probe: probe)

        #expect(treeChanges == 1)
        try await drain(sut)
    }

    @Test
    func `events from a torn-down watcher never reach a later comparison's callbacks`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(factory: factory)
        let probe = AsyncProbe<Void>()
        var treeChanges = 0
        sut.onTreeChanged = {
            treeChanges += 1
            probe.send(())
        }

        let repositoryA = Self.url("/repoA")
        sut.comparisonChanged(rightSource: .directory(repositoryA), repositoryRoot: repositoryA)
        let staleSource = try #require(factory.latest)

        let repositoryB = Self.url("/repoB")
        sut.comparisonChanged(rightSource: .directory(repositoryB), repositoryRoot: repositoryB)
        let freshSource = try #require(factory.all.dropFirst().first)

        // The stale event is dropped; a fresh one proves the pipeline moved on and settles the count.
        staleSource.send(.fileChanged("/repoA/a.swift"))
        try await fire(.fileChanged("/repoB/b.swift"), on: freshSource, after: Self.treeDebounce, probe: probe)

        #expect(treeChanges == 1)
        try await drain(sut)
    }

    @Test
    func `disabling autoRefresh stops the watcher and enabling it reattaches`() async throws {
        let factory = WatcherFactory()
        let sut = makeSUT(isEnabled: true, factory: factory)
        let root = Self.url("/repo")
        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)
        let first = try #require(factory.latest)

        sut.setEnabled(false)
        try await taskProvider.waitForAllTasks()
        #expect(await first.isStopped)

        sut.setEnabled(true)
        let second = try #require(factory.all.dropFirst().first)
        #expect(second !== first)

        let probe = AsyncProbe<Void>()
        sut.onTreeChanged = { probe.send(()) }
        try await fire(.fileChanged("/repo/a.swift"), on: second, after: Self.treeDebounce, probe: probe)
        try await drain(sut)
    }

    @Test
    func `a comparison built with autoRefresh already off never attaches`() {
        let factory = WatcherFactory()
        let sut = makeSUT(isEnabled: false, factory: factory)
        let root = Self.url("/repo")

        sut.comparisonChanged(rightSource: .directory(root), repositoryRoot: root)

        #expect(factory.latest == nil)
    }
}

/// A synthetic ``WatchEventSource`` that records what it watches and lets a test push events.
private actor FakeWatchEventSource: WatchEventSource {
    nonisolated let events: AsyncStream<FileWatcher.FileWatchEvent>
    private let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation
    private(set) var watchedDirectories: [String] = []
    private(set) var watchedFiles: [String] = []
    private(set) var isStopped = false

    init() {
        var captured: AsyncStream<FileWatcher.FileWatchEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func watchDirectory(_ path: String) {
        watchedDirectories.append(path)
    }

    func watchFile(_ path: String) {
        watchedFiles.append(path)
    }

    func unwatchFile(_ path: String) {
        watchedFiles.removeAll { $0 == path }
    }

    func stop() {
        isStopped = true
        continuation.finish()
    }

    /// Delivers `event` to whatever is iterating ``events``; synchronous, so a test calls it without `await`.
    nonisolated func send(_ event: FileWatcher.FileWatchEvent) {
        continuation.yield(event)
    }
}

/// Builds a fresh ``FakeWatchEventSource`` per attachment and keeps each, so a test can tell a superseded source
/// from its successor.
private final class WatcherFactory: Sendable {
    private let sources = Mutex<[FakeWatchEventSource]>([])

    var makeWatcher: @Sendable () -> any WatchEventSource {
        { [self] in
            let source = FakeWatchEventSource()
            sources.withLock { $0.append(source) }
            return source
        }
    }

    var all: [FakeWatchEventSource] { sources.withLock { $0 } }
    var latest: FakeWatchEventSource? { sources.withLock { $0.last } }
}
