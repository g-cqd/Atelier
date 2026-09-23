import AemiRuntime
import AtelierGit
import AtelierProcess
import Foundation
import Testing

@testable import AtelierSources

/// ``SourceLoader/workingTreeStatus(of:)``: git's status, which names paths from the repository root, as a folder
/// source names them.
struct WorkingTreeStatusTests {
    private static func entry(
        _ path: String, originalPath: String? = nil, worktree: GitStatusCode = .modified
    ) -> GitStatusEntry {
        GitStatusEntry(
            path: path, originalPath: originalPath, status: .modified, indexStatus: .unmodified,
            worktreeStatus: worktree)
    }

    @Test
    func `the repository root itself keeps every path as git names it`() {
        let entries = [Self.entry("a.swift"), Self.entry("sub/b.swift")]
        #expect(SourceLoader.entries(entries, under: "") == entries)
    }

    @Test
    func `a subfolder keeps only its own entries, named from the subfolder`() {
        let entries = [
            Self.entry("sub/a.swift", worktree: .untracked), Self.entry("other/b.swift"),
            Self.entry("sub/deep/c.swift"), Self.entry("subway/d.swift"), Self.entry("sub/")
        ]

        let relative = SourceLoader.entries(entries, under: "sub/")

        #expect(relative.map(\.path) == ["a.swift", "deep/c.swift"])
        #expect(relative.first?.worktreeStatus == .untracked)
    }

    @Test
    func `an original path outside the subfolder is dropped and one inside it is renamed too`() {
        let entries = [
            Self.entry("sub/in.swift", originalPath: "sub/was.swift"),
            Self.entry("sub/moved.swift", originalPath: "other/was.swift")
        ]

        let relative = SourceLoader.entries(entries, under: "sub/")

        #expect(relative.map(\.originalPath) == ["was.swift", nil])
    }

    @Test
    func `a folder's prefix is found through symbolic links and nothing outside the root has one`() throws {
        let base = FileManager.default.temporaryDirectory.appending(
            path: "gdv-prefix-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = base.appending(path: "Sources/App", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        // Git names the root by its real path: `/private/var/...` for a folder the caller knows as `/var/...`.
        let realRoot = base.resolvingSymlinksInPath()
        let privateRoot = URL(filePath: "/private" + realRoot.path(percentEncoded: false), directoryHint: .isDirectory)
        let root = FileManager.default.fileExists(atPath: privateRoot.path(percentEncoded: false)) ? privateRoot : base

        #expect(SourceLoader.prefix(of: folder, under: root) == "Sources/App/")
        #expect(SourceLoader.prefix(of: base, under: root) == "")
        #expect(
            SourceLoader.prefix(of: base.appending(path: "Sources", directoryHint: .isDirectory), under: folder) == nil)
        let sibling = URL(
            filePath: String(base.path(percentEncoded: false).dropLast()) + "-sibling", directoryHint: .isDirectory)
        #expect(SourceLoader.prefix(of: sibling, under: base) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a real repository's status reaches a subfolder source in the subfolder's own paths`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-worktree-status-\(UUID().uuidString)", directoryHint: .isDirectory)
        let subfolder = root.appending(path: "sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ arguments: String...) async throws {
            let spec = ProcessSpec(
                executable: GitClient.executable,
                arguments: ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.hooksPath=/dev/null"] + arguments,
                currentDirectory: root, environment: .inherited(overriding: GitClient.hardeningEnvironment))
            let output = try await TestProcesses.runner.run(spec)
            try #require(output.succeeded, "\(output.errorText)")
        }
        func write(_ path: String, _ text: String) throws {
            try text.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
        }
        try await git("init", "-q", "-b", "main")
        try write("sub/edited.swift", "one\n")
        try write("outside.swift", "one\n")
        try await git("add", ".")
        try await git("commit", "-q", "-m", "base")
        try write("sub/edited.swift", "two\n")
        try write("sub/new.swift", "new\n")
        try write("outside.swift", "two\n")

        let fromSubfolder = try #require(try await TestProcesses.loader.workingTreeStatus(of: .directory(subfolder)))
        let fromRoot = try #require(try await TestProcesses.loader.workingTreeStatus(of: .directory(root)))

        let subfolderColumns = Dictionary(uniqueKeysWithValues: fromSubfolder.map { ($0.path, $0.worktreeStatus) })
        #expect(subfolderColumns == ["edited.swift": .modified, "new.swift": .untracked])
        #expect(Set(fromRoot.map(\.path)) == ["sub/edited.swift", "sub/new.swift", "outside.swift"])
    }

    @Test
    func `a ref, a patch and a folder outside every repository have no working-tree status`() async throws {
        let plain = FileManager.default.temporaryDirectory.appending(
            path: "gdv-plain-status-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        let loader = TestProcesses.loader

        #expect(try await loader.workingTreeStatus(of: .directory(plain)) == nil)
        #expect(try await loader.workingTreeStatus(of: .gitRef(repository: plain, ref: "HEAD")) == nil)
        #expect(try await loader.workingTreeStatus(of: .patch(plain.appending(path: "a.diff"), side: .new)) == nil)
    }
}
