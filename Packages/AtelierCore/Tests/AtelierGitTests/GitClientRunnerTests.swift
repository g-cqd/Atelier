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
        let runner = FakeProcessRunner(always: .success("abc123\n"))
        let client = GitClient(repository: Self.repository, runner: runner, timeout: .seconds(10))
        let resolved = try await client.resolve(ref: "main")
        #expect(resolved == "abc123")
        let spec = try #require(runner.specs.first)
        #expect(spec.arguments == ["rev-parse", "--verify", "--quiet", "main^{commit}"])
        #expect(spec.currentDirectory == Self.repository)
        #expect(spec.environment == .inherited(overriding: GitClient.hardeningEnvironment))
        #expect(spec.timeout == .seconds(10))
        #expect(spec.executable == GitClient.executable)
    }

    @Test
    func `a non-zero exit becomes a git error carrying the standard error`() async throws {
        let runner = FakeProcessRunner(always: .failure(128, error: "fatal: bad revision 'nope'\n"))
        let client = GitClient(repository: Self.repository, runner: runner)
        await #expect(throws: GitError.commandFailed("fatal: bad revision 'nope'")) {
            try await client.resolve(ref: "nope")
        }
    }

    @Test
    func `a runner failure becomes a git error naming it`() async throws {
        let runner = FakeProcessRunner { _ in throw ProcessError.timedOut(.seconds(1)) }
        let client = GitClient(repository: Self.repository, runner: runner)
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
        let client = GitClient(repository: Self.repository, runner: runner)
        let run = Task { try await client.workingTreePaths() }
        _ = try await started.wait(forAtLeast: 1)
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }

    @Test
    func `the repository root comes from rev-parse in the directory of the url`() async throws {
        let runner = FakeProcessRunner(always: .success("/repo\n"))
        let file = URL(filePath: "/repo/Sources/a.swift")
        let root = await GitClient.repositoryRoot(containing: file, runner: runner)
        #expect(root == Self.repository)
        #expect(runner.specs.first?.currentDirectory == URL(filePath: "/repo/Sources/"))
        let none = FakeProcessRunner(always: .failure(128, error: "fatal: not a git repository"))
        #expect(await GitClient.repositoryRoot(containing: file, runner: none) == nil)
    }

    @Test
    func `strict isolation scrubs the environment and pins the dangerous configuration keys`() async throws {
        let runner = FakeProcessRunner(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, isolation: .strict)
        _ = try await client.workingTreePaths()
        let spec = try #require(runner.specs.first)
        #expect(spec.arguments.prefix(8) == GitIsolation.strictConfigurationFlags[...])
        #expect(spec.arguments.suffix(from: 8).first == "ls-files")
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
        let runner = FakeProcessRunner(always: .success("build/\u{0}out.log\u{0}"))
        let client = GitClient(repository: Self.repository, runner: runner)
        #expect(try await client.ignoredPaths(collapsingDirectories: true) == ["build/", "out.log"])
        #expect(runner.specs.last?.arguments.last == "--directory")
        _ = try await client.ignoredPaths()
        #expect(runner.specs.last?.arguments.contains("--directory") == false)
        let show = FakeProcessRunner(always: .success("let a = 1\n"))
        let text = try await GitClient(repository: Self.repository, runner: show)
            .content(of: "Sources/a.swift", at: "HEAD")
        #expect(String(decoding: text, as: UTF8.self) == "let a = 1\n")
        #expect(show.specs.first?.arguments == ["show", "HEAD:Sources/a.swift"])
    }
}
