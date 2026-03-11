import Testing
@testable import KittyGit
@testable import KittyFileTree
import Foundation

@Suite
struct KittyGitTests {
    @Test
    func `Parse porcelain output produces correct statuses`() {
        let provider = GitStatusProvider(rootPath: "/project")
        let output = """
         M src/main.swift
        A  src/new.swift
        ?? src/untracked.txt
        D  src/deleted.swift
        R  src/old.swift -> src/renamed.swift
        UU src/conflict.swift
        """
        let (statuses, summary) = provider.parseGitStatus(output, rootPath: "/project")

        #expect(statuses["/project/src/main.swift"] == .modified)
        #expect(statuses["/project/src/new.swift"] == .added)
        #expect(statuses["/project/src/untracked.txt"] == .untracked)
        #expect(statuses["/project/src/deleted.swift"] == .deleted)
        #expect(statuses["/project/src/renamed.swift"] == .renamed)
        #expect(statuses["/project/src/conflict.swift"] == .conflicted)

        #expect(summary.modified == 2)
        #expect(summary.added == 1)
        #expect(summary.untracked == 1)
        #expect(summary.deleted == 1)
        #expect(summary.conflicted == 1)
    }

    @Test
    func `Directory status propagates from children`() {
        let provider = GitStatusProvider(rootPath: "/project")
        let output = " M src/lib/file.swift\n"
        let (statuses, _) = provider.parseGitStatus(output, rootPath: "/project")

        #expect(statuses["/project/src/lib/file.swift"] == .modified)
        #expect(statuses["/project/src/lib"] == .modified)
        #expect(statuses["/project/src"] == .modified)
    }

    @Test
    func `FileStatus indicator strings`() {
        #expect(FileStatus.modified.indicator == "M")
        #expect(FileStatus.added.indicator == "A")
        #expect(FileStatus.untracked.indicator == "?")
        #expect(FileStatus.deleted.indicator == "D")
        #expect(FileStatus.renamed.indicator == "R")
        #expect(FileStatus.conflicted.indicator == "!")
        #expect(FileStatus.ignored.indicator == "I")
        #expect(FileStatus.clean.indicator == "")
    }

    @Test
    func `FileStatusSummary isEmpty`() {
        #expect(FileStatusSummary().isEmpty)
        #expect(!FileStatusSummary(modified: 1).isEmpty)
    }

    @Test
    func `Empty porcelain output produces empty statuses`() {
        let provider = GitStatusProvider(rootPath: "/project")
        let (statuses, summary) = provider.parseGitStatus("", rootPath: "/project")
        #expect(statuses.isEmpty)
        #expect(summary.isEmpty)
    }

    @Test
    func `FileStatus statusColor mapping`() {
        #expect(FileStatus.modified.statusColor == .modified)
        #expect(FileStatus.renamed.statusColor == .modified)
        #expect(FileStatus.added.statusColor == .added)
        #expect(FileStatus.untracked.statusColor == .untracked)
        #expect(FileStatus.deleted.statusColor == .deleted)
        #expect(FileStatus.conflicted.statusColor == .conflicted)
        #expect(FileStatus.clean.statusColor == .clean)
        #expect(FileStatus.ignored.statusColor == .clean)
    }

    @Test
    func `Repository detection works from nested directories`() throws {
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
        #expect(GitStatusProvider.isGitRepository(nestedDirectory.path))
        #expect(GitStatusProvider.repositoryRoot(for: nestedDirectory.path) == tempRoot.path)
    }
}
