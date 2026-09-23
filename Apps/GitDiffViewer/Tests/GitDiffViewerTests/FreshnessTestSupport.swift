import AemiTesting
import AtelierFileTree
import Foundation
import Observation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// A synthetic ``WatchEventSource``: it records the directories watched, and ``write(_:)`` delivers a write the
/// way the one FSEvents stream does, as a directory change at the canonical path and only below a watched directory.
final class FakeWatchEventSource: WatchEventSource, Sendable {
    private struct State {
        var directories: [String] = []
        var isStopped = false
    }

    let events: AsyncStream<FileWatcher.FileWatchEvent>
    private let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation
    private let state = Mutex(State())
    private let watchCalls = CountProbe<String>()

    init() {
        (events, continuation) = AsyncStream.makeStream(of: FileWatcher.FileWatchEvent.self)
    }

    var watchedDirectories: [String] { state.withLock { $0.directories } }
    var isStopped: Bool { state.withLock { $0.isStopped } }

    func watchDirectory(_ path: String) async {
        state.withLock { $0.directories.append(path) }
        watchCalls.record(path)
    }

    func stop() async {
        state.withLock { $0.isStopped = true }
        continuation.finish()
    }

    /// Returns once `count` directories are watched, so a write the stream covers is delivered.
    func waitUntilWatching(_ count: Int) async throws {
        try await watchCalls.wait(forAtLeast: count, timeout: TaskProviderSpy.failureBound)
    }

    /// Delivers `event` as is, whatever the stream covers.
    func send(_ event: FileWatcher.FileWatchEvent) {
        continuation.yield(event)
    }

    /// Delivers a write at `path` when a watched directory covers it.
    /// - Returns: Whether the stream covered it.
    @discardableResult
    func write(_ path: String) -> Bool {
        let isCovered = state.withLock { state in
            state.directories.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        if isCovered { continuation.yield(.directoryChanged(path)) }
        return isCovered
    }
}

/// A ``RepositoryFreshness`` over synthetic watchers and a virtual clock, with the waits its suites share.
@MainActor
struct WatcherHarness {
    static let treeDebounce: Duration = .milliseconds(600)
    static let refDebounce: Duration = .milliseconds(150)

    let taskProvider = TaskProviderSpy.tolerant()
    let clock = TestClock()

    func makeSUT(isEnabled: Bool = true, factory: WatcherFactory = WatcherFactory()) -> RepositoryFreshness {
        RepositoryFreshness(
            taskProvider: taskProvider, isEnabled: isEnabled, clock: clock, treeDebounce: Self.treeDebounce,
            refDebounce: Self.refDebounce, makeWatcher: factory.makeWatcher)
    }

    static func url(_ path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Sends `event`, waits for its debounce to sleep on `clock`, advances past `duration`, then waits for `probe`.
    func fire(
        _ event: FileWatcher.FileWatchEvent, on source: FakeWatchEventSource, after duration: Duration,
        probe: AsyncProbe<Void>
    ) async throws {
        source.send(event)
        try await clock.waitForSleepers()
        clock.advance(by: duration)
        _ = try await probe.next()
    }

    /// Delivers a write at `path` through the stream's coverage, then advances past its debounce and waits for `probe`.
    func write(
        _ path: String, on source: FakeWatchEventSource, after duration: Duration, probe: AsyncProbe<Void>
    ) async throws {
        try #require(source.write(path), "\(path) lies outside every watched directory")
        try await clock.waitForSleepers()
        clock.advance(by: duration)
        _ = try await probe.next()
    }

    /// Stops `sut`'s watcher and drains every task behind it: tasks left to unwind on their own pile up across the
    /// suite and starve the cooperative pool.
    func drain(_ sut: RepositoryFreshness) async throws {
        sut.teardown()
        try await taskProvider.waitForAllTasks()
        try await taskProvider.waitForObservationsToFinish()
    }
}

/// Builds a fresh ``FakeWatchEventSource`` per attachment and keeps each, so a test can tell a superseded source
/// from its successor.
final class WatcherFactory: Sendable {
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

/// A linked worktree's layout on disk: a root whose `.git` file points to a private git dir inside the main
/// repository's, which a `commondir` file points back to. Paths are canonical, as the watcher reports them.
struct LinkedWorktree {
    let base: URL
    let rootURL: URL
    let root: String
    let privateGitDir: String
    let commonGitDir: String

    init() throws {
        base = FileManager.default.temporaryDirectory.appending(
            path: "freshness-worktree-\(UUID().uuidString)", directoryHint: .isDirectory)
        rootURL = base.appending(path: "worktree", directoryHint: .isDirectory)
        let common = base.appending(path: "main/.git", directoryHint: .isDirectory)
        let privateDir = common.appending(path: "worktrees/feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: privateDir, withIntermediateDirectories: true)
        try "gitdir: \(privateDir.path(percentEncoded: false))\n"
            .write(to: rootURL.appending(path: ".git"), atomically: true, encoding: .utf8)
        try "../..\n".write(to: privateDir.appending(path: "commondir"), atomically: true, encoding: .utf8)
        root = Self.canonical(rootURL)
        privateGitDir = Self.canonical(privateDir)
        commonGitDir = Self.canonical(common)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Moves the private git dir, as `git worktree repair` after a rename leaves it, and repoints `.git` at it.
    /// - Returns: The new private git dir, canonical.
    func movePrivateGitDir(to name: String) throws -> String {
        let common = base.appending(path: "main/.git", directoryHint: .isDirectory)
        let moved = common.appending(path: "worktrees/\(name)", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: common.appending(path: "worktrees/feature"), to: moved)
        try "gitdir: \(moved.path(percentEncoded: false))\n"
            .write(to: rootURL.appending(path: ".git"), atomically: true, encoding: .utf8)
        return Self.canonical(moved)
    }

    private static func canonical(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.hasSuffix("/") { path.removeLast() }
        return FileWatcher.canonicalPaths(forFile: path).first ?? path
    }
}

/// A ``SourceReading`` scripted the way git answers: entries per source, taken when a listing is asked for and handed
/// back once its gate opens, so a write during a listing is not in it; a commit per ref, which a test moves; the
/// paths git ignores; the ignored files per source, or a failure to list them. It counts what it was asked.
final class ScriptedGitReader: SourceReading, Sendable {
    private struct State {
        var entries: [ComparisonSource: [SourceEntry]] = [:]
        var ignoredEntries: [ComparisonSource: [SourceEntry]] = [:]
        var ignoredListingFailure: String?
        var repositories: [URL: RepositoryInfo] = [:]
        var statuses: [ComparisonSource: [GitStatusEntry]] = [:]
        var commits: [String: String] = [:]
        var ignoredPaths: Set<String> = []
        var ignoreCheckFailure: String?
        var listingGates: [ComparisonSource: ListingGate] = [:]
        var listings: [ComparisonSource: Int] = [:]
        var ignoredListings = 0
        var ignoreChecks: [[String]] = []
        var repositoryInfoReads = 0
    }

    private let state = Mutex(State())

    var entries: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.entries } }
        set { state.withLock { $0.entries = newValue } }
    }

    var ignoredEntries: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.ignoredEntries } }
        set { state.withLock { $0.ignoredEntries = newValue } }
    }

    /// When set, every listing of the ignored files fails with this message.
    var ignoredListingFailure: String? {
        get { state.withLock { $0.ignoredListingFailure } }
        set { state.withLock { $0.ignoredListingFailure = newValue } }
    }

    var repositories: [URL: RepositoryInfo] {
        get { state.withLock { $0.repositories } }
        set { state.withLock { $0.repositories = newValue } }
    }

    var statuses: [ComparisonSource: [GitStatusEntry]] {
        get { state.withLock { $0.statuses } }
        set { state.withLock { $0.statuses = newValue } }
    }

    /// The commit each ref resolves to; a ref without one resolves to itself.
    var commits: [String: String] {
        get { state.withLock { $0.commits } }
        set { state.withLock { $0.commits = newValue } }
    }

    /// The paths git ignores, as `check-ignore` reports them.
    var ignoredPaths: Set<String> {
        get { state.withLock { $0.ignoredPaths } }
        set { state.withLock { $0.ignoredPaths = newValue } }
    }

    /// When set, every `check-ignore` fails with this message.
    var ignoreCheckFailure: String? {
        get { state.withLock { $0.ignoreCheckFailure } }
        set { state.withLock { $0.ignoreCheckFailure = newValue } }
    }

    /// Holds the next listing of `source` at the returned gate, with the entries as they stand when it gets there.
    func gateNextListing(of source: ComparisonSource) -> ListingGate {
        let gate = ListingGate()
        state.withLock { $0.listingGates[source] = gate }
        return gate
    }

    /// How many times `source` was listed.
    func listings(of source: ComparisonSource) -> Int {
        state.withLock { $0.listings[source] ?? 0 }
    }

    var ignoredListings: Int { state.withLock { $0.ignoredListings } }
    /// The paths each `check-ignore` was asked about, in order.
    var ignoreChecks: [[String]] { state.withLock { $0.ignoreChecks } }
    var repositoryInfoReads: Int { state.withLock { $0.repositoryInfoReads } }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? {
        state.withLock { state in
            state.repositoryInfoReads += 1
            return state.repositories[url]
        }
    }

    func entries(of source: ComparisonSource) async throws -> [SourceEntry] {
        let (listed, gate) = state.withLock { state in
            state.listings[source, default: 0] += 1
            return (state.entries[source] ?? [], state.listingGates.removeValue(forKey: source))
        }
        if let gate { try await gate.hold() }
        return listed
    }

    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        let (listed, failure) = state.withLock { state in
            state.ignoredListings += 1
            return (state.ignoredEntries[source] ?? [], state.ignoredListingFailure)
        }
        if let failure { throw ScriptedFailure(message: failure) }
        return listed
    }

    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        "\(entry.relativePath) \(entry.blobID ?? "")\n"
    }

    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] {
        [:]
    }

    func resolve(ref: String, in repository: URL) async throws -> String {
        state.withLock { $0.commits[ref] } ?? ref
    }

    func workingTreeStatus(of source: ComparisonSource) async throws -> [GitStatusEntry]? {
        state.withLock { $0.statuses[source] }
    }

    func ignoredPaths(among paths: [String], in source: ComparisonSource) async throws -> Set<String> {
        let (ignored, failure) = state.withLock { state in
            state.ignoreChecks.append(paths)
            return (state.ignoredPaths.intersection(paths), state.ignoreCheckFailure)
        }
        if let failure { throw ScriptedFailure(message: failure) }
        return ignored
    }
}

/// One listing held by a ``ScriptedGitReader``: ``reached`` gets an element when the listing arrives, and the
/// listing goes on once ``open()`` is called.
final class ListingGate: Sendable {
    let reached = AsyncProbe<Void>()
    private let opened = AsyncProbe<Void>()

    func open() {
        opened.send(())
    }

    fileprivate func hold() async throws {
        reached.send(())
        _ = try await opened.next()
    }
}

/// The failure a ``ScriptedGitReader`` reports, carrying the message git would have printed.
struct ScriptedFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Returns once `condition` holds, reading it again only when an observable property it reads changes: the wait for
/// a model's state that a sleeping debounce keeps ``TaskProviderSpy/waitForAllTasks(timeout:)`` from reporting.
@MainActor
func awaitObserved(_ condition: @escaping @MainActor () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
