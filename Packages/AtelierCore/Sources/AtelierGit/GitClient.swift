public import AtelierProcess
public import Foundation

import func AemiRuntime.mapConcurrently

public enum GitError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case notARepository

    public var errorDescription: String? {
        switch self {
            case .commandFailed(let message): message.trimmingCharacters(in: .whitespacesAndNewlines)
            case .notARepository: "Not a git repository"
        }
    }
}

/// Git as a set of async methods over one repository, each parsed by the matching ``GitParsers`` function. Every
/// run inherits the parent's environment with ``hardeningEnvironment`` on top, so git never waits on a terminal
/// prompt or an optional lock.
public struct GitClient: Sendable {
    /// Variables set on every git run: no credential prompt on a closed standard input, no optional index locks.
    public static let hardeningEnvironment = ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]

    public let repository: URL
    private let runner: any ProcessRunner
    private let timeout: Duration?

    /// - Parameters:
    ///   - repository: The repository root every command runs in.
    ///   - runner: How git is spawned; the app owns the pool behind it, tests inject a fake.
    ///   - timeout: The budget of one git run on the runner's clock; nil lets a run take as long as it needs.
    public init(repository: URL, runner: any ProcessRunner, timeout: Duration? = nil) {
        self.repository = repository
        self.runner = runner
        self.timeout = timeout
    }

    /// The root of the repository `url` lies in, or nil when it lies in none.
    public static func repositoryRoot(containing url: URL, runner: any ProcessRunner) async -> URL? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let data = try? await run(["rev-parse", "--show-toplevel"], in: directory, runner: runner)
        else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }

    public func info() async throws -> RepositoryInfo {
        async let branches = references(pattern: "refs/heads", "refs/remotes")
        async let tags = references(pattern: "refs/tags")
        async let commits = recentCommits(limit: 200)
        return try await RepositoryInfo(root: repository, branches: branches, tags: tags, commits: commits)
    }

    public func resolve(ref: String) async throws -> String {
        let data = try await run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files of the tree at `ref`, filtered to the supported extensions.
    public func tree(at ref: String, isSupported: @Sendable (String) -> Bool) async throws -> [GitTreeEntry] {
        GitParsers.tree(try await run(["ls-tree", "-r", "-l", "-z", ref]), isSupported: isSupported)
    }

    /// Files of the working tree as git sees it: tracked files plus untracked ones that are not ignored. Index
    /// entries whose file is gone are listed too; the caller drops what it cannot stat.
    public func workingTreePaths() async throws -> [String] {
        GitParsers.paths(try await run(["ls-files", "-z", "--cached", "--others", "--exclude-standard"]))
    }

    /// Untracked files git ignores.
    public func ignoredPaths() async throws -> [String] {
        GitParsers.paths(try await run(["ls-files", "-z", "--others", "--ignored", "--exclude-standard"]))
    }

    public func blob(_ id: String) async throws -> Data {
        try await run(["cat-file", "blob", id])
    }

    /// Contents of many blobs through one `cat-file --batch` process instead of one process per blob.
    /// Missing ids are left out of the result.
    public func blobs(_ ids: [String]) async throws -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let output = try await run(["cat-file", "--batch"], input: Data((ids.joined(separator: "\n") + "\n").utf8))
        return GitParsers.batch(output)
    }

    /// Renames between two refs, or between a ref and the working tree when `to` is nil, old path to new path.
    public func renames(from: String, to: String?) async throws -> [String: String] {
        GitParsers.renames(
            try await run(["diff", "--name-status", "-M", "-z", "--diff-filter=R", from] + (to.map { [$0] } ?? [])))
    }

    private func references(pattern: String...) async throws -> [String] {
        GitParsers.references(
            try await run(["for-each-ref", "--format=%(refname:short)", "--sort=-committerdate"] + pattern))
    }

    private func recentCommits(limit: Int) async throws -> [GitCommit] {
        GitParsers.commits(try await run(["log", "--format=%H%x1f%h%x1f%s", "-n", String(limit)]))
    }

    private func run(_ arguments: [String], input: Data? = nil) async throws -> Data {
        try await Self.run(arguments, input: input, in: repository, runner: runner, timeout: timeout)
    }

    /// Where git lives: `GDV_GIT` when it names an executable, else the first `git` on `PATH` or in the usual
    /// toolchain locations, `/usr/bin/git` last because that one is a shim that re-resolves the developer directory
    /// on every launch.
    public static let executable: URL = ExecutableResolver(
        overrideVariable: "GDV_GIT",
        searchPaths: [
            "/Applications/Xcode.app/Contents/Developer/usr/bin", "/Library/Developer/CommandLineTools/usr/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"
        ],
        excludedPaths: ["/usr/bin"]
    )
    .resolve("git")

    /// Runs git and returns its standard output; a non-zero exit becomes a ``GitError`` carrying its standard error,
    /// a runner failure becomes a ``GitError`` naming it, and cancelling the task terminates git.
    private static func run(
        _ arguments: [String], input: Data? = nil, in directory: URL, runner: any ProcessRunner,
        timeout: Duration? = nil
    ) async throws -> Data {
        PhaseTrace.log("git \(arguments.prefix(2).joined(separator: " "))")
        defer { PhaseTrace.log("git done \(arguments.prefix(2).joined(separator: " "))") }
        let spec = ProcessSpec(
            executable: executable, arguments: arguments, currentDirectory: directory,
            environment: .inherited(overriding: hardeningEnvironment), standardInput: input, timeout: timeout)
        let output: ProcessOutput
        do {
            output = try await runner.run(spec)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw GitError.commandFailed("could not run git: \(error)")
        }
        guard output.succeeded else { throw GitError.commandFailed(output.errorText) }
        return output.standardOutput
    }
}

extension GitCommit {
    /// The short form of a full SHA-1 or SHA-256 hash, for labels; anything else is shown as typed.
    public static func abbreviated(_ ref: String) -> String {
        guard ref.count == 40 || ref.count == 64, ref.allSatisfy(\.isHexDigit) else { return ref }
        return String(ref.prefix(7))
    }
}
