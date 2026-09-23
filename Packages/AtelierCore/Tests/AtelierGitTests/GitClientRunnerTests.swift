import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// `GitClient` over a scripted runner: what it asks git for and how it reports what comes back.
@Suite(.tags(.concurrency))
struct GitClientRunnerTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)

    @Test
    func `every run carries the hardening variables, the repository and the arguments`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("abc123\n"))
        let client = GitClient(
            repository: Self.repository, runner: runner, timeout: .seconds(10), gate: GitConfigGate())
        let resolved = try await client.resolve(ref: "main")
        #expect(resolved == "abc123")
        let spec = try #require(runner.commandSpecs.first)
        #expect(
            spec.arguments
                == GitIsolation.strictConfigurationFlags + [
                    "rev-parse", "--verify", "--quiet", "--end-of-options", "main^{commit}"
                ])
        #expect(spec.currentDirectory == Self.repository)
        #expect(spec.environment == GitIsolation.strict.environment)
        #expect(spec.timeout == .seconds(10))
        #expect(spec.executable == GitClient.executable)
    }

    @Test
    func `a non-zero exit becomes a git error carrying the standard error`() async throws {
        let runner = FakeProcessRunner.gated(always: .failure(128, error: "fatal: bad revision 'nope'\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.commandFailed("fatal: bad revision 'nope'")) {
            try await client.resolve(ref: "nope")
        }
    }

    @Test
    func `a runner failure becomes a git error naming it`() async throws {
        let runner = FakeProcessRunner { _ in throw ProcessError.timedOut(.seconds(1)) }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.self) { try await client.workingTreePaths() }
    }

    @Test(.timeLimit(.minutes(1)))
    func `cancelling the caller surfaces as a cancellation, not a git error`() async throws {
        let parked = AsyncLatch()
        let started = AsyncEventProbe<Void>()
        let runner = FakeProcessRunner { _ in
            started.record(())
            try await parked.wait()
            return .success("")
        }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        let run = Task { try await client.workingTreePaths() }
        _ = try await started.wait(forAtLeast: 1)
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }

    @Test
    func `the repository root comes from rev-parse in the directory of the url`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("/repo\n"))
        let file = URL(filePath: "/repo/Sources/a.swift")
        let root = await GitClient.repositoryRoot(containing: file, runner: runner, gate: GitConfigGate())
        #expect(root == Self.repository)
        #expect(runner.commandSpecs.first?.currentDirectory == URL(filePath: "/repo/Sources/"))
        let none = FakeProcessRunner.gated(always: .failure(128, error: "fatal: not a git repository"))
        #expect(await GitClient.repositoryRoot(containing: file, runner: none, gate: GitConfigGate()) == nil)
    }

    @Test
    func `the repository root is read, configuration included, within the timeout given`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("/repo\n"))

        _ = await GitClient.repositoryRoot(
            containing: Self.repository, runner: runner, timeout: .seconds(7), gate: GitConfigGate())

        #expect(!runner.specs.isEmpty)
        #expect(runner.specs.allSatisfy { $0.timeout == .seconds(7) })
    }

    @Test
    func `strict isolation scrubs the environment and pins the dangerous configuration keys`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, isolation: .strict, gate: GitConfigGate())
        _ = try await client.workingTreePaths()
        let spec = try #require(runner.commandSpecs.first)
        let flags = GitIsolation.strictConfigurationFlags
        #expect(spec.arguments.prefix(flags.count) == flags[...])
        #expect(spec.arguments.suffix(from: flags.count).first == "ls-files")
        #expect(flags.contains("diff.external=") && flags.contains("core.pager=cat"))
        guard case .exactly(let variables) = spec.environment else {
            Issue.record("expected an exact environment")
            return
        }
        #expect(variables["GIT_TERMINAL_PROMPT"] == "0")
        #expect(variables["GIT_CONFIG_NOSYSTEM"] == "1")
        #expect(variables["LC_ALL"] == "C")
        #expect(variables["GIT_SSH_COMMAND"] == nil)
    }

    @Test
    func `ignored paths collapse directories on request and content comes from show`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("build/\u{0}out.log\u{0}"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        #expect(try await client.ignoredPaths(collapsingDirectories: true) == ["build/", "out.log"])
        #expect(runner.commandSpecs.last?.arguments.last == "--directory")
        _ = try await client.ignoredPaths()
        #expect(runner.commandSpecs.last?.arguments.contains("--directory") == false)
        let show = FakeProcessRunner.gated(always: .success("let a = 1\n"))
        let text = try await GitClient(repository: Self.repository, runner: show, gate: GitConfigGate())
            .content(of: "Sources/a.swift", at: "HEAD")
        #expect(String(decoding: text, as: UTF8.self) == "let a = 1\n")
        #expect(
            show.commandSpecs.first?.arguments.suffix(2)
                == ["show", "--end-of-options", "HEAD:Sources/a.swift"].suffix(2))
    }

    @Test
    func `an inheriting client keeps the caller's environment and passes no configuration flags`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("abc\n"))
        let client = GitClient(
            repository: Self.repository, runner: runner, isolation: .inheriting, gate: GitConfigGate())
        _ = try await client.resolve(ref: "main")
        let spec = try #require(runner.commandSpecs.first)
        #expect(spec.arguments.first == "rev-parse")
        #expect(spec.environment == .inherited(overriding: GitClient.hardeningEnvironment))
    }

    @Test
    func `branches and tags are thin wrappers over for-each-ref`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("main\norigin/main\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        #expect(try await client.branches() == ["main", "origin/main"])
        #expect(runner.commandSpecs.last?.arguments.suffix(2) == ["refs/heads", "refs/remotes"])

        let tags = FakeProcessRunner.gated(always: .success("v1.0\n"))
        let tagClient = GitClient(repository: Self.repository, runner: tags, gate: GitConfigGate())
        #expect(try await tagClient.tags() == ["v1.0"])
        #expect(tags.commandSpecs.last?.arguments.suffix(1) == ["refs/tags"])
    }

    @Test
    func `remotes runs remote -v`() async throws {
        let runner = FakeProcessRunner.gated(
            always: .success("origin\tgit@x:y.git (fetch)\norigin\tgit@x:y.git (push)\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        let remotes = try await client.remotes()
        #expect(remotes == [GitRemote(name: "origin", fetchURL: "git@x:y.git")])
        #expect(runner.commandSpecs.last?.arguments.suffix(2) == ["remote", "-v"])
    }

    @Test
    func `aheadBehind sends checked refs behind rev-list left-right`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("2\t5\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        let counts = try await client.aheadBehind("main", upstream: "origin/main")
        #expect(counts.ahead == 2)
        #expect(counts.behind == 5)
        #expect(
            runner.commandSpecs.last?.arguments.suffix(5)
                == ["rev-list", "--left-right", "--count", "--end-of-options", "main...origin/main"])
    }

    @Test
    func `aheadBehind refuses option-shaped refs before running git`() async {
        let runner = FakeProcessRunner.gated(always: .success("0\t0\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.invalidArgument("--evil")) {
            try await client.aheadBehind("--evil", upstream: "main")
        }
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `fetch builds the expected argv with prune and refspecs`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch(remote: "origin", refspecs: ["refs/heads/main:refs/remotes/origin/main"], prune: true)
        let spec = try #require(runner.commandSpecs.first)
        #expect(
            spec.arguments.suffix(6) == [
                "fetch", "--prune", "--no-recurse-submodules", "--end-of-options",
                "git@github.com:aemi/atelier.git", "refs/heads/main:refs/remotes/origin/main"
            ])
    }

    @Test
    func `fetch rejects an option-shaped remote or refspec before running git`() async {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.invalidArgument("-x")) { try await client.fetch(remote: "-x") }
        await #expect(throws: GitError.invalidArgument("-y")) {
            try await client.fetch(refspecs: ["-y"])
        }
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `fetch runs under networking isolation with a per-call timeout, regardless of the client's own isolation`()
        async throws
    {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(
            repository: Self.repository, runner: runner, timeout: .seconds(5), isolation: .strict, gate: GitConfigGate()
        )
        try await client.fetch(timeout: .seconds(45))
        let spec = try #require(runner.commandSpecs.first)
        #expect(spec.timeout == .seconds(45))
        #expect(spec.environment == GitIsolation.networking.environment)
        #expect(
            Array(spec.arguments.prefix(GitIsolation.networkingConfigurationFlags.count))
                == GitIsolation.networkingConfigurationFlags)
        #expect(!spec.arguments.contains("core.sshCommand=/usr/bin/false"))
        #expect(spec.arguments.contains("core.sshCommand=ssh"))
    }

    @Test
    func `networking isolation pins core sshCommand instead of leaving it for the repository's config to win`()
        async throws
    {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        let spec = try #require(runner.commandSpecs.first)
        // Replaced, never dropped: an omitted key lets the repository's own configuration choose the command.
        #expect(spec.arguments.contains("core.sshCommand=ssh"))
        #expect(!spec.arguments.contains("core.sshCommand=/usr/bin/false"))
    }

    @Test
    func `networking isolation keeps authentication variables but strips repository-selection ones`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        let spec = try #require(runner.commandSpecs.first)
        guard case .exactly(let variables) = spec.environment else {
            Issue.record("expected an exact environment for networking isolation")
            return
        }
        #expect(variables["GIT_TERMINAL_PROMPT"] == "0")
        #expect(variables["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(variables["HOME"] == ProcessInfo.processInfo.environment["HOME"])
        for variable in GitIsolation.repositorySelectionVariables {
            #expect(variables[variable] == nil, "\(variable) must not reach a networking git run")
        }
    }

    @Test(arguments: ["--output=/tmp/x", "-", "", "a\nb", "a\u{0}b"])
    func `an option-shaped or unprintable ref never reaches git`(ref: String) async {
        let runner = FakeProcessRunner.gated(always: .success("abc\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.invalidArgument(ref)) { try await client.resolve(ref: ref) }
        await #expect(throws: GitError.invalidArgument(ref)) { try await client.tree(at: ref) { _ in true } }
        await #expect(throws: GitError.invalidArgument(ref)) { try await client.content(of: "p", at: ref) }
        await #expect(throws: GitError.invalidArgument(ref)) { try await client.renames(from: "HEAD", to: ref) }
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `refs and paths sit behind --end-of-options in every command that takes one`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        _ = try? await client.tree(at: "v1") { _ in true }
        _ = try? await client.renames(from: "a", to: "b")
        _ = try? await client.content(of: "dir/f", at: "v1")
        for spec in runner.commandSpecs {
            let arguments = Array(spec.arguments.drop(while: { $0 == "-c" || $0.contains("=") }))
            let marker = try #require(arguments.firstIndex(of: "--end-of-options"))
            #expect(!arguments[(marker + 1)...].isEmpty)
            #expect(arguments[(marker + 1)...].allSatisfy { !$0.hasPrefix("-") })
        }
    }
}
