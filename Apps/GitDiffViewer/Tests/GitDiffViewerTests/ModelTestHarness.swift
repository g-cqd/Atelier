import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// The model under test with its doubles: an in-memory source reader, a task provider spy the tests settle on,
/// a hand-advanced uptime and a test clock. Shared by every model suite.
@MainActor
struct ModelTestHarness {
    let taskProvider = TaskProviderSpy.tolerant()
    let reader = FakeSourceReader()
    let uptime = FakeUptime()
    let clock = TestClock()
    static let leftURL = URL(filePath: "/left", directoryHint: .isDirectory)
    static let rightURL = URL(filePath: "/right", directoryHint: .isDirectory)

    /// Removes the suites `makeSUT` created once the harness, and with it the test, is gone.
    private let defaultsCleanup = DefaultsCleanup()

    func makeSUT() -> DiffViewerModel {
        let suite = "GitDiffViewerTests.model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defaultsCleanup.register(suite)
        return DiffViewerModel(
            settings: ViewerSettings(defaults: defaults), reader: reader, taskProvider: taskProvider,
            uptime: uptime.provider, clock: clock)
    }

    func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    /// Loads both folders; the model recomputes the comparison itself once both sides land.
    func load(_ sut: DiffViewerModel) async throws {
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
    }

    /// Drags `handle` of `marker` by `rows` rows along its direction and lets go, as the gutter reports a drag.
    func drag(_ sut: DiffViewerModel, _ handle: GapHandle, of marker: GapMarker, rows: Int) {
        sut.handleGapDrag(.began(marker, handle, lineHeight: 10))
        sut.handleGapDrag(.moved(offset: CGFloat(rows) * 10 * handle.revealDirection, edgeOvershoot: 0))
        sut.handleGapDrag(.ended)
    }

    /// Thirty lines on each side of `a.swift`, blob 1 against blob 2, which differ at line 15 alone: a file with one
    /// hunk between a leading and a trailing gap.
    func serveOneChangeInTheMiddle() {
        let lines = (1 ... 30).map { "line \($0)" }
        var changed = lines
        changed[14] = "line fifteen"
        reader.blobContents["1"] = lines.joined(separator: "\n") + "\n"
        reader.blobContents["2"] = changed.joined(separator: "\n") + "\n"
    }

    /// Holds every listing of the folder at `url` until the returned gate gets one element per listing. Keyed the
    /// way the reader looks it up: a folder's path ends with a slash, so `"/right"` would hold nothing.
    func holdListing(of url: URL) -> AsyncProbe<Void> {
        let gate = AsyncProbe<Void>()
        reader.gate[url.path(percentEncoded: false)] = gate
        return gate
    }
}

/// Forgets the persistent domains a test's models wrote, so no preference file outlives the run.
final class DefaultsCleanup: Sendable {
    private let suites = Mutex<[String]>([])

    func register(_ suite: String) {
        suites.withLock { $0.append(suite) }
    }

    deinit {
        for suite in suites.withLock({ $0 }) {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

/// A monotonic time the test advances by hand, read by the model as nanoseconds.
final class FakeUptime: Sendable {
    private let nanoseconds = Mutex<Int64>(0)

    var now: Duration {
        get { .nanoseconds(nanoseconds.withLock { $0 }) }
        set {
            let components = newValue.components
            nanoseconds.withLock { $0 = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000 }
        }
    }

    /// The provider shape the model takes.
    var provider: @Sendable () -> Int64 {
        { [self] in nanoseconds.withLock { $0 } }
    }
}

/// In-memory source reader; records the paths whose content was requested and can hold a read until released.
final class FakeSourceReader: SourceReading, Sendable {
    private struct State {
        var entries: [ComparisonSource: [SourceEntry]] = [:]
        var ignored: [ComparisonSource: [SourceEntry]] = [:]
        var repositories: [URL: RepositoryInfo] = [:]
        var contents: [String: String] = [:]
        var blobContents: [String: String] = [:]
        var gate: [String: AsyncProbe<Void>] = [:]
        var gitRenames: [String: String] = [:]
        var commits: [String: String] = [:]
        var workingTreeStatuses: [ComparisonSource: [GitStatusEntry]] = [:]
        var entriesReads = 0
        var failingListings: [ComparisonSource: String] = [:]
        var failingContents: [String: String] = [:]
    }

    /// The error a failing listing or read throws, with the message a test chose.
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let state = Mutex(State())
    let contentRequests = AsyncProbe<String>()
    let repositoryInfoRequests = AsyncProbe<URL>()
    let workingTreeStatusRequests = AsyncProbe<ComparisonSource>()

    /// Git's status per source, as ``workingTreeStatus(of:)`` serves it; a source without one is no working tree.
    var workingTreeStatuses: [ComparisonSource: [GitStatusEntry]] {
        get { state.withLock { $0.workingTreeStatuses } }
        set { state.withLock { $0.workingTreeStatuses = newValue } }
    }

    /// How many times any source's entries were listed.
    var entriesReads: Int { state.withLock { $0.entriesReads } }

    /// Sources whose listing throws, with the message it throws.
    var failingListings: [ComparisonSource: String] {
        get { state.withLock { $0.failingListings } }
        set { state.withLock { $0.failingListings = newValue } }
    }

    /// Paths whose reads throw, with the message they throw.
    var failingContents: [String: String] {
        get { state.withLock { $0.failingContents } }
        set { state.withLock { $0.failingContents = newValue } }
    }

    var entries: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.entries } }
        set { state.withLock { $0.entries = newValue } }
    }

    var contents: [String: String] {
        get { state.withLock { $0.contents } }
        set { state.withLock { $0.contents = newValue } }
    }

    /// Contents by blob id, served ahead of ``contents``, so the two sides of one path can differ.
    var blobContents: [String: String] {
        get { state.withLock { $0.blobContents } }
        set { state.withLock { $0.blobContents = newValue } }
    }

    var ignored: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.ignored } }
        set { state.withLock { $0.ignored = newValue } }
    }

    var repositories: [URL: RepositoryInfo] {
        get { state.withLock { $0.repositories } }
        set { state.withLock { $0.repositories = newValue } }
    }

    /// Reads of a path, entries of a directory path, or `status:` plus a directory path for its git status, wait for
    /// one element per read on their gate.
    var gate: [String: AsyncProbe<Void>] {
        get { state.withLock { $0.gate } }
        set { state.withLock { $0.gate = newValue } }
    }

    var gitRenames: [String: String] {
        get { state.withLock { $0.gitRenames } }
        set { state.withLock { $0.gitRenames = newValue } }
    }

    /// The commit each ref resolves to, which a test moves the way a commit or a checkout does; a ref without one
    /// resolves to itself, and so never moves.
    var commits: [String: String] {
        get { state.withLock { $0.commits } }
        set { state.withLock { $0.commits = newValue } }
    }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? {
        repositoryInfoRequests.send(url)
        if let gate = gate["repositoryInfo:\(url.path(percentEncoded: false))"] {
            _ = try? await gate.next()
        }
        return repositories[url]
    }

    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] { gitRenames }

    func resolve(ref: String, in repository: URL) async throws -> String {
        commits[ref] ?? ref
    }

    func entries(of source: ComparisonSource) async throws -> [SourceEntry] {
        state.withLock { $0.entriesReads += 1 }
        if case .directory(let url) = source, let gate = gate[url.path(percentEncoded: false)] {
            _ = try await gate.next()
        }
        if let message = failingListings[source] { throw Failure(message: message) }
        return entries[source] ?? []
    }

    /// Serves ``workingTreeStatuses`` as they stand once the source's `status:` gate, if any, lets the read through.
    /// The gate is taken before the request is announced, so a test that saw the request may drop the gate for the
    /// reads after it.
    func workingTreeStatus(of source: ComparisonSource) async throws -> [GitStatusEntry]? {
        var held: AsyncProbe<Void>?
        if case .directory(let url) = source { held = gate["status:\(url.path(percentEncoded: false))"] }
        workingTreeStatusRequests.send(source)
        if let held { _ = try await held.next() }
        return workingTreeStatuses[source]
    }

    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        ignored[source] ?? []
    }

    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        contentRequests.send(entry.relativePath)
        if let gate = gate[entry.relativePath] {
            _ = try await gate.next()
        }
        if let message = failingContents[entry.relativePath] { throw Failure(message: message) }
        if let blobID = entry.blobID, let content = blobContents[blobID] { return content }
        return contents[entry.relativePath] ?? "\(entry.relativePath) \(entry.blobID ?? "")\n"
    }
}

/// Renders like the live renderer, except that while ``isHolding`` each render step announces the file indices it
/// renders on ``steps`` and waits for one element on ``release``, so a test can act while a render step runs.
final class HoldingPaneRenderer: Sendable {
    let steps = AsyncProbe<[Int]>()
    let release = AsyncProbe<Void>()
    private let holding = Mutex(false)

    var isHolding: Bool {
        get { holding.withLock { $0 } }
        set { holding.withLock { $0 = newValue } }
    }

    var renderer: PaneRenderer {
        PaneRenderer { [self] jobs, options, layout in
            if isHolding {
                steps.send(jobs.map(\.index))
                _ = try await release.next()
            }
            return try await PaneRenderer.live.render(jobs, options: options, layout: layout)
        }
    }
}
