import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import KittyFileTree
@testable import KittyGit

/// Joins NUL-terminated `status --porcelain=v2 -z` records the way git emits them.
private func porcelain(_ records: [String]) -> ProcessOutput {
    ProcessOutput(
        terminationStatus: 0, standardOutput: Data((records.joined(separator: "\u{0}") + "\u{0}").utf8),
        standardError: Data())
}

@Suite
struct KittyGitTests {
    @Test
    func `a refresh reads the branch, every status and the summary from one porcelain v2 status`() async {
        let runner = FakeProcessRunner { spec in
            #expect(spec.arguments.contains("--porcelain=v2"))
            return porcelain([
                "# branch.head main", "1 .M N... 100644 100644 100644 aaaa bbbb Sources/a.swift",
                "1 A. N... 000000 100644 100644 0000 bbbb Sources/deep/new.swift", "? notes.txt",
                "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc c.swift"
            ])
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()
        #expect(provider.branchName == "main")
        #expect(provider.status(for: "/project/Sources/a.swift") == .modified)
        #expect(provider.status(for: "/project/Sources/deep/new.swift") == .added)
        #expect(provider.status(for: "/project/Sources/deep") == .added)
        #expect(provider.status(for: "/project/Sources") == .modified)
        #expect(provider.status(for: "/project/notes.txt") == .untracked)
        #expect(provider.status(for: "/project/c.swift") == .conflicted)
        #expect(provider.status(for: "/project/other.swift") == nil)
        #expect(provider.summary == FileStatusSummary(modified: 1, added: 1, untracked: 1, deleted: 0, conflicted: 1))
        #expect(runner.specs.count == 1)
        guard case .exactly(let environment) = runner.specs[0].environment else {
            Issue.record("git must run under the strict environment")
            return
        }
        #expect(environment["GIT_CONFIG_NOSYSTEM"] == "1")
        #expect(runner.specs[0].timeout == GitStatusProvider.gitTimeout)
    }

    @Test
    func `a failing git leaves everything clean`() async {
        let runner = FakeProcessRunner(always: .failure(128, error: "fatal: not a git repository"))
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()
        #expect(provider.branchName == nil)
        #expect(provider.summary.isEmpty)
        #expect(provider.status(for: "/project/a.swift") == nil)
    }

    @Test
    func `FileStatus indicator strings`() {
        #expect(FileStatus.modified.indicator == "M")
        #expect(FileStatus.added.indicator == "A")
        #expect(FileStatus.untracked.indicator == "?")
        #expect(FileStatus.deleted.indicator == "D")
        #expect(FileStatus.conflicted.indicator == "!")
        #expect(FileStatus.clean.indicator == "")
    }

    @Test
    func `FileStatus statusColor mapping`() {
        #expect(FileStatus.modified.statusColor == .modified)
        #expect(FileStatus.renamed.statusColor == .modified)
        #expect(FileStatus.added.statusColor == .added)
        #expect(FileStatus.untracked.statusColor == .untracked)
        #expect(FileStatus.deleted.statusColor == .deleted)
        #expect(FileStatus.conflicted.statusColor == .conflicted)
        #expect(FileStatus.ignored.statusColor == .clean)
    }

    @Test
    func `Repository detection works from nested directories`() async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nestedDirectory = tempRoot.appendingPathComponent("Sources/Nested", isDirectory: true)

        try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "-q"]
        process.currentDirectoryURL = tempRoot
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)

        let isRepository = await GitStatusProvider.isGitRepository(nestedDirectory.path, runner: runner)
        #expect(isRepository)
        let root = await GitStatusProvider.repositoryRoot(for: nestedDirectory.path, runner: runner)
        #expect(root == tempRoot.path)
    }

    @Test
    func `line decorations come from the shared diff: modified, added, and deletions anchored below`() {
        #expect(
            GitStatusProvider.lineDecorations(
                base: ["alpha", "beta", "gamma"], current: ["alpha", "delta", "epsilon", "gamma"], addedColor: .added
            )
            .markers == [1: .modified, 2: .added])
        #expect(
            GitStatusProvider.lineDecorations(
                base: ["alpha", "beta", "gamma"], current: ["alpha", "gamma"], addedColor: .added
            )
            .markers == [1: .deleted])
        #expect(
            GitStatusProvider.lineDecorations(
                base: ["alpha", "beta", "gamma"], current: ["alpha", "beta"], addedColor: .added
            )
            .markers == [1: .deleted])
        #expect(GitStatusProvider.lineDecorations(base: [], current: [], addedColor: .added).isEmpty)
        #expect(GitStatusProvider.lineDecorations(base: ["a"], current: ["a"], addedColor: .added).isEmpty)
    }

    @Test
    func `an untracked file is marked on every line and a committed file's base comes from git show`() async {
        let runner = FakeProcessRunner { spec in
            if spec.arguments.contains("--porcelain=v2") {
                return porcelain(["? loose.txt", "1 .M N... 100644 100644 100644 aaaa bbbb tracked.txt"])
            }
            #expect(
                spec.arguments == ["show", "HEAD:tracked.txt"]
                    || spec.arguments.suffix(2) == ["show", "HEAD:tracked.txt"])
            return .success("one\ntwo\n")
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()
        let untracked = await provider.lineDecorations(for: "/project/loose.txt", lines: ["x", "y"])
        #expect(untracked.markers == [0: .untracked, 1: .untracked])
        let tracked = await provider.lineDecorations(for: "/project/tracked.txt", lines: ["one", "TWO", ""])
        #expect(tracked.markers == [1: .modified])
        // The base is cached: a second request spawns no further git.
        let specs = runner.specs.count
        _ = await provider.lineDecorations(for: "/project/tracked.txt", lines: ["one", "two", ""])
        #expect(runner.specs.count == specs)
    }

    @Test
    func `Added line decorations mark every visible line and empty input yields none`() {
        #expect(
            GitStatusProvider.addedLineDecorations(for: ["alpha", "beta", ""], color: .untracked).markers
                == [0: .untracked, 1: .untracked, 2: .untracked])
        #expect(GitStatusProvider.addedLineDecorations(for: [], color: .added).isEmpty)
    }
}
