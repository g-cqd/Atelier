import AemiTesting
import DiffGit
import Foundation
import Synchronization

import class AemiRuntime.BlockingOffloadPool

/// A repository in a temporary directory, built with the real git on a pool thread so the main actor never waits on
/// it, for the model tests that read a real history.
struct GitRepositoryFixture: Sendable {
    /// The threads the fixtures' git runs and the real loaders over them use; the process exits with the test run.
    static let pool = BlockingOffloadPool(width: 4)

    let root: URL

    private init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    /// A new repository that `build` fills, off the main actor.
    static func make(_ build: @escaping @Sendable (GitRepositoryFixture) throws -> Void) async throws
        -> GitRepositoryFixture
    {
        try await pool.run {
            let fixture = try GitRepositoryFixture()
            try build(fixture)
            return fixture
        }
    }

    /// Removes the repository, off the main actor.
    func remove() async {
        let root = root
        _ = try? await Self.pool.run { try FileManager.default.removeItem(at: root) }
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: root.appending(path: relativePath))
    }

    /// Stages everything and commits it with `message`, returning the new commit's id.
    @discardableResult
    func commit(_ message: String) throws -> String {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
        return try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git outside the code under test, with an identity and no signing, template or hooks, and returns its
    /// standard output; a failing run throws.
    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = GitClient.executable
        process.arguments =
            [
                "-c", "user.name=Tess Ter", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                "-c", "init.templateDir=", "-c", "core.hooksPath=/dev/null"
            ] + arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed("git \(arguments.joined(separator: " ")) exited \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A real loader whose batch reads from one source land only once ``release`` opens, announcing each on ``held``:
/// a render that asked for them is superseded meanwhile, and its result comes back late.
final class HoldingSourceReader: SourceReading {
    let base: SourceLoader
    let heldSource: ComparisonSource
    let held = AsyncProbe<Void>()
    let release = ReleaseGate()

    init(base: SourceLoader, holding source: ComparisonSource) {
        self.base = base
        heldSource = source
    }

    func contents(of entries: [SourceEntry], in source: ComparisonSource) async throws -> [String: String] {
        let texts = try await base.contents(of: entries, in: source)
        guard source == heldSource, !entries.isEmpty else { return texts }
        held.send(())
        await release.wait()
        return texts
    }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? { await base.repositoryInfo(containing: url) }
    func entries(of source: ComparisonSource) async throws -> [SourceEntry] { try await base.entries(of: source) }
    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        try await base.ignoredEntries(of: source)
    }
    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        try await base.content(of: entry, in: source)
    }
    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] {
        await base.renames(from: left, to: right)
    }
    func resolve(ref: String, in repository: URL) async throws -> String {
        try await base.resolve(ref: ref, in: repository)
    }
    func workingTreeStatus(of source: ComparisonSource) async throws -> [GitStatusEntry]? {
        try await base.workingTreeStatus(of: source)
    }
    func ignoredPaths(among paths: [String], in source: ComparisonSource) async throws -> Set<String> {
        try await base.ignoredPaths(among: paths, in: source)
    }
}

/// A gate that stays shut until opened, whatever happens to the tasks waiting at it: a cancelled render's read still
/// lands, late, as a slow git's would.
final class ReleaseGate: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isOpen = state.withLock { state in
                if !state.isOpen { state.waiters.append(continuation) }
                return state.isOpen
            }
            if isOpen { continuation.resume() }
        }
    }

    func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}
