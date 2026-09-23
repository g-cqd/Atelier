import AemiTestKit
import AtelierGit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierSources

/// Every git run the loader starts has a budget, so a git that never answers, as one reading a FIFO a repository's
/// configuration names does, is terminated instead of holding a pool thread for good (Sec M2).
struct LoaderGitTimeoutTests {
    @Test(.timeLimit(.minutes(1)))
    func `a git run that hangs times out instead of holding the loader`() async throws {
        let clock = TestClock()
        // A git that never answers, ended when the spec's budget runs out, as the hardened runner ends it.
        let runner = FakeProcessRunner { spec in
            try await clock.sleep(for: spec.timeout ?? .seconds(365 * 24 * 3600))
            throw ProcessError.timedOut(spec.timeout ?? .zero)
        }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: runner, offload: pool)
        let repository = URL(filePath: "/repo", directoryHint: .isDirectory)

        // A child task, so that the time limit's cancellation reaches the call if it hangs anyway.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await #expect(throws: GitError.self) { try await loader.resolve(ref: "main", in: repository) }
            }
            try await clock.waitForSleepers(atLeast: 1)
            clock.advance(by: SourceLoader.gitTimeout)
            try await group.waitForAll()
        }
    }

    @Test
    func `every git run the loader starts carries the loader's budget`() async throws {
        let root = try LoaderOffloadTests.folder(["a.swift": "let a = 1\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let toplevel = root.standardizedFileURL.path(percentEncoded: false)
        let runner = FakeProcessRunner { spec in
            if spec.arguments.contains("--show-toplevel") { return .success(toplevel + "\n") }
            if spec.arguments.contains("ls-files") { return .success("a.swift\0") }
            // The configuration listing, and every other command: an empty answer.
            return .success("")
        }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: runner, offload: pool)
        let folder = ComparisonSource.directory(root)
        let head = ComparisonSource.gitRef(repository: root, ref: "HEAD")
        let entry = GitTreeEntry(relativePath: "a.swift", blobID: "abc123", size: 10)

        _ = await loader.repositoryInfo(containing: root)
        _ = try await loader.entries(of: folder)
        _ = try await loader.ignoredEntries(of: folder)
        _ = try await loader.entries(of: head)
        _ = try await loader.content(of: entry, in: head)
        _ = try await loader.contents(of: [entry], in: head)
        _ = try await loader.resolve(ref: "HEAD", in: root)
        _ = await loader.renames(from: head, to: folder)
        _ = await loader.renames(from: head, to: .gitRef(repository: root, ref: "main"))
        _ = try await loader.workingTreeStatus(of: folder)
        _ = try await loader.ignoredPaths(among: ["a.swift"], in: folder)

        let untimed = runner.specs.filter { $0.timeout != SourceLoader.gitTimeout }.map(\.arguments)
        #expect(runner.specs.count > 11)
        #expect(untimed.isEmpty)
    }
}
