import AemiRuntime
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// What `GitClient` asks git when a caller only needs to know which paths git ignores: a status without the ignored
/// files, and `check-ignore` over many paths at once, whose exit status 1 means "none of them".
struct GitClientIgnoreTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)

    // MARK: Status

    @Test
    func `a status without ignored files asks git to skip them`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        _ = try await client.status(includingIgnored: false)

        let arguments = try #require(runner.commandSpecs.first?.arguments)
        #expect(arguments.contains("--ignored=no"))
        #expect(!arguments.contains("--ignored=matching"))
    }

    @Test
    func `a status lists the ignored files unless asked not to`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        _ = try await client.status()

        #expect(runner.commandSpecs.first?.arguments.contains("--ignored=matching") == true)
    }

    // MARK: check-ignore, scripted

    @Test
    func `every path reaches check-ignore on its standard input, none as an argument`() async throws {
        let runner = FakeProcessRunner.gated(always: .success("-rf\u{0}"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        let ignored = try await client.ignored(among: ["-rf", "a b.swift"])

        let spec = try #require(runner.commandSpecs.first)
        #expect(spec.arguments.suffix(3) == ["check-ignore", "-z", "--stdin"])
        #expect(spec.standardInput == Data("-rf\u{0}a b.swift\u{0}".utf8))
        #expect(spec.environment == GitIsolation.strict.environment)
        #expect(ignored == ["-rf"])
    }

    @Test
    func `check-ignore failing for good is an error, not an empty answer`() async {
        let runner = FakeProcessRunner.gated(always: .failure(128, error: "fatal: not a git repository\n"))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        await #expect(throws: GitError.commandFailed("fatal: not a git repository")) {
            try await client.ignored(among: ["a.swift"])
        }
    }

    @Test
    func `a path no record carries or git would read as pathspec magic is never judged`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        #expect(try await client.ignored(among: ["", "nul\u{0}inside", ":(glob)x", ":/top"]).isEmpty)
        #expect(runner.specs.isEmpty)
    }

    // MARK: check-ignore, real git

    @Test
    func `check-ignore names the ignored paths among many, whether or not they exist, and never a tracked one`()
        async throws
    {
        let repository = try ScratchRepository()
        defer { repository.remove() }
        try repository.write(".gitignore", "build/\nxcuserdata/\nforced.txt\n")
        try repository.write("forced.txt", "tracked despite the rule\n")
        try repository.git("add", "-f", ".gitignore", "forced.txt")
        try repository.git("commit", "-q", "-m", "rules")

        let userState = "App.xcodeproj/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate"

        let ignored = try await repository.client().ignored(among: ["build/out.o", userState, "a.swift", "forced.txt"])

        #expect(ignored == ["build/out.o", userState])
    }

    @Test
    func `check-ignore ignoring none of the paths answers with an empty set, not an error`() async throws {
        let repository = try ScratchRepository()
        defer { repository.remove() }
        try repository.write(".gitignore", "build/\n")

        let ignored = try await repository.client().ignored(among: ["Sources/a.swift", "README.md"])

        #expect(ignored.isEmpty)
    }
}

/// A repository in a temporary directory, built with the real git, and a client over it.
private struct ScratchRepository {
    let root: URL
    private let pool = BlockingOffloadPool(width: 2)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "atelier-ignore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    func remove() {
        pool.shutdown()
        try? FileManager.default.removeItem(at: root)
    }

    /// A client with a verdict cache of its own, so no test sees another's.
    func client() -> GitClient {
        GitClient(
            repository: root, runner: HardenedProcessRunner(pool: pool), timeout: .seconds(30), gate: GitConfigGate())
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Runs git outside the client under test, with an identity and no signing, template or hooks.
    func git(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = GitClient.executable
        process.arguments =
            [
                "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "init.templateDir=",
                "-c", "core.hooksPath=/dev/null"
            ] + arguments
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
