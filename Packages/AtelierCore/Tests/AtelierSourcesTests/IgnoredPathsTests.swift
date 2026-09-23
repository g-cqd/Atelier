import AtelierGit
import AtelierProcess
import Foundation
import Testing

@testable import AtelierSources

/// What a working-tree folder's watcher asks git through ``SourceLoader``: which of the paths that changed git
/// ignores, and a status for the badges that skips the ignored files altogether.
struct IgnoredPathsTests {
    /// A repository whose `.gitignore` names `build/`, with one committed file edited and one build product.
    private struct Repository {
        let root: URL

        init() async throws {
            root = FileManager.default.temporaryDirectory.appending(
                path: "gdv-ignored-paths-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: root.appending(path: "build", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try await git("init", "-q", "-b", "main")
            try write(".gitignore", "build/\n")
            try write("a.swift", "one\n")
            try await git("add", ".")
            try await git("commit", "-q", "-m", "base")
            try write("a.swift", "two\n")
            try write("build/out.txt", "product\n")
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        private func git(_ arguments: String...) async throws {
            let spec = ProcessSpec(
                executable: GitClient.executable,
                arguments: [
                    "-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null", "-c",
                    "init.templateDir="
                ] + arguments,
                currentDirectory: root, environment: .inherited(overriding: GitClient.hardeningEnvironment))
            let output = try await TestProcesses.runner.run(spec)
            try #require(output.succeeded, "\(output.errorText)")
        }

        private func write(_ path: String, _ text: String) throws {
            try text.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `the working tree's status for badges leaves the ignored files out`() async throws {
        let repository = try await Repository()
        defer { repository.remove() }

        let status = try #require(try await TestProcesses.loader.workingTreeStatus(of: .directory(repository.root)))

        #expect(status.map(\.path) == ["a.swift"])
        #expect(!status.contains { $0.worktreeStatus == .ignored })
    }

    @Test(.timeLimit(.minutes(1)))
    func `a folder's ignored paths are the ones git ignores among those asked about`() async throws {
        let repository = try await Repository()
        defer { repository.remove() }

        let ignored = try await TestProcesses.loader.ignoredPaths(
            among: ["build/out.txt", "build/later.o", "a.swift", "new.swift"], in: .directory(repository.root))

        #expect(ignored == ["build/out.txt", "build/later.o"])
    }

    @Test
    func `a ref or a patch ignores nothing and runs no git`() async throws {
        let root = URL(filePath: "/nowhere", directoryHint: .isDirectory)
        let ref = ComparisonSource.gitRef(repository: root, ref: "HEAD")
        let patch = ComparisonSource.patch(root.appending(path: "a.diff"), side: .new)

        #expect(try await TestProcesses.loader.ignoredPaths(among: ["a"], in: ref).isEmpty)
        #expect(try await TestProcesses.loader.ignoredPaths(among: ["a"], in: patch).isEmpty)
    }
}
