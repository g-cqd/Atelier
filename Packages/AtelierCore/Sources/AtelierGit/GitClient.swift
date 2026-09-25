public import AtelierProcess
public import Foundation

import func AemiRuntime.mapConcurrently

public enum GitError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case notARepository
    /// A ref, object id or path that could be read as an option or break the command line.
    case invalidArgument(String)
    /// The repository's own configuration holds keys that can make git run a command it chose, so no command ran.
    /// The keys are named without their values, which can hold a token or a path the user did not choose.
    case refusedConfiguration([String])
    /// A fetch URL that is neither `https` nor `ssh`, or a remote with no URL at all.
    case unsupportedRemoteURL(String)

    public var errorDescription: String? {
        switch self {
            case .commandFailed(let message): message.trimmingCharacters(in: .whitespacesAndNewlines)
            case .notARepository: "Not a git repository"
            case .invalidArgument(let value): "Not a usable git reference or path: \(value)"
            case .refusedConfiguration(let keys):
                """
                This repository's git configuration can make git run commands it chose, so git was not run. \
                Refused keys: \(keys.joined(separator: ", "))
                """
            case .unsupportedRemoteURL(let url):
                "Only an https or ssh remote can be fetched from; this one is: \(url)"
        }
    }
}

/// Git as a set of async methods over one repository, each parsed by the matching ``GitParsers`` function. Every
/// run inherits the parent's environment with ``hardeningEnvironment`` on top, so git never waits on a terminal
/// prompt or an optional lock.
///
/// Before any command runs in a repository, its own configuration is read and judged by ``GitConfigPolicy``: a
/// repository that can make git run a command it chose gets no command at all, and every method throws
/// ``GitError/refusedConfiguration(_:)``. The verdict is cached per repository in ``GitConfigGate`` and re-read
/// when a configuration file changes, so the check costs one git process per configuration change, not one per
/// command.
public struct GitClient: Sendable {
    /// Variables set on every git run: no credential prompt on a closed standard input, no optional index locks.
    public static let hardeningEnvironment = ["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]

    public let repository: URL
    private let runner: any ProcessRunner
    private let timeout: Duration?
    private let isolation: GitIsolation
    private let gate: GitConfigGate

    /// - Parameters:
    ///   - repository: The repository root every command runs in.
    ///   - runner: How git is spawned; the app owns the pool behind it, tests inject a fake.
    ///   - timeout: The budget of one git run on the runner's clock; nil lets a run take as long as it needs.
    ///   - isolation: How much of the caller's environment and of the repository's configuration git may see.
    ///   - gate: Where the configuration verdict of a repository is read and cached; the shared one unless a test
    ///     wants a cache of its own.
    public init(
        repository: URL, runner: any ProcessRunner, timeout: Duration? = nil, isolation: GitIsolation = .strict,
        gate: GitConfigGate = .shared
    ) {
        self.repository = repository
        self.runner = runner
        self.timeout = timeout
        self.isolation = isolation
        self.gate = gate
    }

    /// The root of the repository `url` lies in, or nil when it lies in none, when its configuration is refused, or
    /// when git does not answer within `timeout`, a budget on the runner's clock that nil leaves open.
    public static func repositoryRoot(
        containing url: URL, runner: any ProcessRunner, timeout: Duration? = nil, isolation: GitIsolation = .strict,
        gate: GitConfigGate = .shared
    ) async -> URL? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard
            let data = try? await run(
                ["rev-parse", "--show-toplevel"], in: directory, runner: runner, timeout: timeout,
                isolation: isolation, gate: gate)
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
        let data = try await run([
            "rev-parse", "--verify", "--quiet", "--end-of-options", "\(try Self.checked(ref))^{commit}"
        ])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files of the tree at `ref`, filtered to the supported extensions.
    public func tree(at ref: String, isSupported: @Sendable (String) -> Bool) async throws -> [GitTreeEntry] {
        GitParsers.tree(
            try await run(["ls-tree", "-r", "-l", "-z", "--end-of-options", try Self.checked(ref)]),
            isSupported: isSupported)
    }

    /// The branch and every path that is not clean, untracked files listed one by one, and ignored files unless
    /// `includingIgnored` is false. Leaving them out spares git its walk through every ignored directory, the
    /// costliest part of the read in a tree full of build output.
    ///
    /// Changes inside a submodule's own working tree are left out: reading them makes git enter the submodule and
    /// obey *its* `.git/config`, which ``GitConfigPolicy`` never saw. A submodule whose recorded commit moved is
    /// still reported.
    public func status(includingIgnored: Bool = true) async throws -> GitStatusSnapshot {
        GitParsers.porcelainV2(
            try await run([
                "status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all",
                includingIgnored ? "--ignored=matching" : "--ignored=no", "--ignore-submodules=dirty"
            ]))
    }

    /// The paths among `paths`, relative to ``repository``, that git ignores, judged by one `git check-ignore`
    /// reading them all from its standard input, where no path can pass for an option and glob characters match
    /// themselves. A tracked path is never reported, since the index outranks every ignore rule, and a path need not
    /// exist: the rules match names. A path no record can carry (a NUL) or that git would read as pathspec magic (a
    /// leading `:`, which `check-ignore` either refuses or reads as another path) is never judged, so never ignored.
    /// - Throws: ``GitError`` when git fails, for example outside a repository.
    public func ignored(among paths: [String]) async throws -> Set<String> {
        let names = paths.filter { !$0.isEmpty && !$0.hasPrefix(":") && !$0.utf8.contains(0) }
        guard !names.isEmpty else { return [] }
        let verdict = try await Self.approvedConfiguration(
            in: repository, runner: runner, timeout: timeout, isolation: isolation, gate: gate)
        let output = try await Self.execute(
            ["check-ignore", "-z", "--stdin"],
            input: Data((names.joined(separator: "\0") + "\0").utf8), in: repository, runner: runner, timeout: timeout,
            isolation: isolation, extraConfiguration: Self.mitigationFlags(for: verdict, isolation: isolation))
        // check-ignore exits with 1 when it ignores none of the paths, and with 128 when it fails.
        switch output.terminationStatus {
            case 0: return Set(GitParsers.paths(output.standardOutput))
            case 1: return []
            default: throw GitError.commandFailed(output.errorText)
        }
    }

    /// Files of the working tree as git sees it: tracked files plus untracked ones that are not ignored. Index
    /// entries whose file is gone are listed too; the caller drops what it cannot stat.
    public func workingTreePaths() async throws -> [String] {
        GitParsers.paths(try await run(["ls-files", "-z", "--cached", "--others", "--exclude-standard"]))
    }

    /// Untracked files git ignores; with `collapsingDirectories`, a directory that is ignored as a whole is one
    /// entry with a trailing slash instead of every file under it, which is what a tree filter wants.
    public func ignoredPaths(collapsingDirectories: Bool = false) async throws -> [String] {
        var arguments = ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"]
        if collapsingDirectories { arguments.append("--directory") }
        return GitParsers.paths(try await run(arguments))
    }

    /// The contents of `path` as committed at `ref`, through `git show`.
    /// - Throws: ``GitError`` when the path does not exist at that ref.
    public func content(of path: String, at ref: String) async throws -> Data {
        try await run(["show", "--end-of-options", "\(try Self.checked(ref)):\(try Self.checked(path))"])
    }

    public func blob(_ id: String) async throws -> Data {
        try await run(["cat-file", "blob", try Self.checked(id)])
    }

    /// Contents of many blobs through one `cat-file --batch` process instead of one process per blob.
    /// Missing ids are left out of the result.
    public func blobs(_ ids: [String]) async throws -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let output = try await run(["cat-file", "--batch"], input: Data((ids.joined(separator: "\n") + "\n").utf8))
        return GitParsers.batch(output)
    }

    /// Renames between two refs, or between a ref and the working tree when `to` is nil, old path to new path.
    ///
    /// `--no-ext-diff` and `--no-textconv` keep an external diff or a textconv driver out of the run, and
    /// `--ignore-submodules=dirty` keeps git from entering a submodule, whose own configuration the gate never saw;
    /// none of the three can change which paths a rename filter reports.
    public func renames(from: String, to: String?) async throws -> [String: String] {
        GitParsers.renames(
            try await run(
                [
                    "diff", "--no-ext-diff", "--no-textconv", "--ignore-submodules=dirty", "--name-status", "-M",
                    "-z", "--diff-filter=R", "--end-of-options", try Self.checked(from)
                ] + (try to.map { [try Self.checked($0)] } ?? [])))
    }

    private func references(pattern: String...) async throws -> [String] {
        GitParsers.references(
            try await run(["for-each-ref", "--format=%(refname:short)", "--sort=-committerdate"] + pattern))
    }

    /// Local and remote-tracking branches, most recently committed first, without the rest of ``info()``.
    public func branches() async throws -> [String] {
        try await references(pattern: "refs/heads", "refs/remotes")
    }

    /// Tags, most recently committed first; see ``branches()``.
    public func tags() async throws -> [String] {
        try await references(pattern: "refs/tags")
    }

    /// `--no-show-signature` because a repository that sets `log.showSignature` makes `git log` run the signature
    /// program on every commit that carries a `gpgsig` header; the pinned `gpg.program` is the second layer.
    private func recentCommits(limit: Int) async throws -> [GitCommit] {
        GitParsers.commits(
            try await run(["log", "--no-show-signature", "--format=%H%x1f%h%x1f%s", "-n", String(limit)]))
    }

    /// The repository's remotes, one per name, with their `fetch` URL; a remote with only a `push` line is left
    /// out.
    public func remotes() async throws -> [GitRemote] {
        GitParsers.remotes(try await run(["remote", "-v"]))
    }

    /// How many commits `local` has that `upstream` does not (`ahead`), and the reverse (`behind`).
    public func aheadBehind(_ local: String, upstream: String) async throws -> (ahead: Int, behind: Int) {
        try GitParsers.aheadBehind(
            try await run([
                "rev-list", "--left-right", "--count", "--end-of-options",
                "\(try Self.checked(local))...\(try Self.checked(upstream))"
            ]))
    }

    /// Fetches from `remote`, `refspecs` when given, pruning stale remote-tracking branches on request. Runs under
    /// ``GitIsolation/networking`` whatever the client's isolation, with `timeout` in place of the client's budget.
    ///
    /// The fetch goes to the remote's URL, not to its name, and only when that URL is `https` or `ssh`
    /// (``GitConfigPolicy/transportURL(_:)``): fetching by name lets the repository pick the transport, and
    /// `remote.<name>.uploadpack` with a local path is one of the ways it then runs a command. Without `refspecs`
    /// the remote's own are used, so remote-tracking branches still move, and a remote that configured none gets the
    /// default one.
    /// - Throws: ``GitError/unsupportedRemoteURL(_:)`` for a remote with no URL or a URL of another scheme,
    ///   ``GitError/refusedConfiguration(_:)`` when the repository's configuration is refused.
    public func fetch(
        remote: String = "origin", refspecs: [String] = [], prune: Bool = false, timeout: Duration = .seconds(120)
    ) async throws {
        let name = try Self.checked(remote)
        let checkedRefspecs = try refspecs.map(Self.checked)
        let verdict = try await Self.approvedConfiguration(
            in: repository, runner: runner, timeout: timeout, isolation: .networking, gate: gate)
        guard let configured = verdict.value(forKey: "remote.\(name).url") else {
            throw GitError.unsupportedRemoteURL("\(name) has no URL")
        }
        guard let url = GitConfigPolicy.transportURL(configured) else {
            throw GitError.unsupportedRemoteURL(GitConfigPolicy.redacted(configured))
        }
        let configuredRefspecs = verdict.values(forKey: "remote.\(name).fetch")
        let effective =
            checkedRefspecs.isEmpty
            ? (configuredRefspecs.isEmpty ? ["+refs/heads/*:refs/remotes/\(name)/*"] : configuredRefspecs)
            : checkedRefspecs
        // `--no-recurse-submodules`: a submodule fetch would run under the submodule's own configuration.
        let arguments =
            ["fetch"] + (prune ? ["--prune"] : []) + ["--no-recurse-submodules", "--end-of-options", url]
            + (try effective.map(Self.checked))
        _ = try await Self.spawn(
            arguments, in: repository, runner: runner, timeout: timeout, isolation: .networking,
            extraConfiguration: Self.mitigationFlags(for: verdict, isolation: .networking))
    }

    /// A ref, object id or path as git may see it on the command line: not empty, not option-shaped, and free of
    /// the bytes that end an argument or a record. `--end-of-options` guards the commands too; this refuses the
    /// value outright so a planted ref such as `--output=~/.zshrc` never reaches git at all.
    static func checked(_ value: String) throws(GitError) -> String {
        guard !value.isEmpty, !value.hasPrefix("-"), !value.utf8.contains(0), !value.utf8.contains(0x0A) else {
            throw .invalidArgument(value)
        }
        return value
    }

    func run(_ arguments: [String], input: Data? = nil) async throws -> Data {
        try await Self.run(
            arguments, input: input, in: repository, runner: runner, timeout: timeout, isolation: isolation,
            gate: gate)
    }

    /// Runs git once the repository's configuration has been approved, and returns how it exited, for a command
    /// whose exit status is part of its answer (`merge-base --is-ancestor` answers "no" with 1).
    /// - Throws: ``GitError/refusedConfiguration(_:)`` before git runs when the configuration is refused; a
    ///   ``GitError`` naming a runner failure; a cancellation when the task is cancelled. A non-zero exit is returned,
    ///   not thrown.
    func runReadingStatus(_ arguments: [String]) async throws -> ProcessOutput {
        let verdict = try await Self.approvedConfiguration(
            in: repository, runner: runner, timeout: timeout, isolation: isolation, gate: gate)
        return try await Self.execute(
            arguments, in: repository, runner: runner, timeout: timeout, isolation: isolation,
            extraConfiguration: Self.mitigationFlags(for: verdict, isolation: isolation))
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

    /// Runs git once the repository's configuration has been approved, and returns its standard output.
    /// - Throws: ``GitError/refusedConfiguration(_:)`` before git runs when the configuration is refused; otherwise
    ///   as ``spawn(_:input:in:runner:timeout:isolation:extraConfiguration:)``.
    private static func run(
        _ arguments: [String], input: Data? = nil, in directory: URL, runner: any ProcessRunner,
        timeout: Duration? = nil, isolation: GitIsolation = .strict, gate: GitConfigGate = .shared
    ) async throws -> Data {
        let verdict = try await approvedConfiguration(
            in: directory, runner: runner, timeout: timeout, isolation: isolation, gate: gate)
        return try await spawn(
            arguments, input: input, in: directory, runner: runner, timeout: timeout, isolation: isolation,
            extraConfiguration: mitigationFlags(for: verdict, isolation: isolation))
    }

    /// The repository's configuration verdict, read through `gate` and cached there.
    /// - Throws: ``GitError/refusedConfiguration(_:)`` when a key falls outside ``GitConfigPolicy``'s allowlist, so
    ///   that no command runs in that repository at all.
    static func approvedConfiguration(
        in directory: URL, runner: any ProcessRunner, timeout: Duration?, isolation: GitIsolation,
        gate: GitConfigGate
    ) async throws -> GitConfigVerdict {
        let verdict = try await gate.verdict(in: directory, isolation: isolation) {
            try await spawn(
                GitConfigPolicy.listingArguments, in: directory, runner: runner, timeout: timeout,
                isolation: isolation)
        }
        guard verdict.isApproved else { throw GitError.refusedConfiguration(verdict.refusedKeys) }
        return verdict
    }

    /// The `-c` flags one repository's verdict adds to its commands: every filter driver it defines blanked, and,
    /// for a fetch, the credential helpers defined outside the repository put back after the pins reset the list.
    static func mitigationFlags(for verdict: GitConfigVerdict, isolation: GitIsolation) -> [String] {
        var flags = GitConfigPolicy.filterBlankingFlags(for: verdict.filterDrivers)
        if isolation == .networking {
            flags += verdict.userCredentialHelpers.flatMap { ["-c", "credential.helper=\($0)"] }
        }
        return flags
    }

    /// Runs git and returns its standard output; a non-zero exit becomes a ``GitError`` carrying its standard error,
    /// a runner failure becomes a ``GitError`` naming it, and cancelling the task terminates git.
    private static func spawn(
        _ arguments: [String], input: Data? = nil, in directory: URL, runner: any ProcessRunner,
        timeout: Duration? = nil, isolation: GitIsolation = .strict, extraConfiguration: [String] = []
    ) async throws -> Data {
        let output = try await execute(
            arguments, input: input, in: directory, runner: runner, timeout: timeout, isolation: isolation,
            extraConfiguration: extraConfiguration)
        guard output.succeeded else { throw GitError.commandFailed(output.errorText) }
        return output.standardOutput
    }

    /// Runs git with the isolation's flags and environment and returns how it exited, for the caller to judge; a
    /// runner failure becomes a ``GitError`` naming it, and cancelling the task terminates git.
    private static func execute(
        _ arguments: [String], input: Data? = nil, in directory: URL, runner: any ProcessRunner,
        timeout: Duration? = nil, isolation: GitIsolation = .strict, extraConfiguration: [String] = []
    ) async throws -> ProcessOutput {
        PhaseTrace.log("git \(arguments.prefix(2).joined(separator: " "))")
        defer { PhaseTrace.log("git done \(arguments.prefix(2).joined(separator: " "))") }
        let spec = ProcessSpec(
            executable: executable, arguments: isolation.configurationFlags + extraConfiguration + arguments,
            currentDirectory: directory, environment: isolation.environment, standardInput: input, timeout: timeout)
        do {
            return try await runner.run(spec)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw GitError.commandFailed("could not run git: \(error)")
        }
    }
}

extension GitCommit {
    /// The short form of a full SHA-1 or SHA-256 hash, for labels; anything else is shown as typed.
    public static func abbreviated(_ ref: String) -> String {
        guard ref.count == 40 || ref.count == 64, ref.allSatisfy(\.isHexDigit) else { return ref }
        return String(ref.prefix(7))
    }
}
