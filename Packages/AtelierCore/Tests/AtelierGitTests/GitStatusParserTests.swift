import AemiRuntime
import AtelierProcess
import Foundation
import Testing

@testable import AtelierGit

/// `git status --porcelain=v2 -z --branch` records, parsed without a process.
struct GitStatusParserTests {
    /// Joins NUL-terminated records the way git emits them with `-z`.
    private static func records(_ fields: [String]) -> Data {
        Data((fields.joined(separator: "\u{0}") + "\u{0}").utf8)
    }

    @Test
    func `branch headers give the head, the upstream and the ahead-behind counts`() {
        let data = Self.records([
            "# branch.oid 0123abcd", "# branch.head main", "# branch.upstream origin/main", "# branch.ab +2 -1"
        ])
        let snapshot = GitParsers.porcelainV2(data)
        #expect(snapshot.branch == GitBranchStatus(head: "main", upstream: "origin/main", ahead: 2, behind: 1))
        #expect(snapshot.entries.isEmpty)
    }

    @Test
    func `a detached head has no branch name`() {
        let snapshot = GitParsers.porcelainV2(Self.records(["# branch.oid 0123abcd", "# branch.head (detached)"]))
        #expect(snapshot.branch?.head == nil)
        #expect(snapshot.branch?.ahead == 0)
    }

    @Test(arguments: [
        ("1 .M N... 100644 100644 100644 aaaa bbbb Sources/a.swift", "Sources/a.swift", FileStatus.modified),
        ("1 M. N... 100644 100644 100644 aaaa bbbb b.swift", "b.swift", .modified),
        ("1 MM N... 100644 100644 100644 aaaa bbbb c.swift", "c.swift", .modified),
        ("1 A. N... 000000 100644 100644 0000 bbbb new.swift", "new.swift", .added),
        ("1 AM N... 000000 100644 100644 0000 bbbb new2.swift", "new2.swift", .added),
        ("1 D. N... 100644 000000 000000 aaaa 0000 gone.swift", "gone.swift", .deleted),
        ("1 .D N... 100644 100644 000000 aaaa aaaa gone2.swift", "gone2.swift", .deleted),
        ("1 .T N... 100644 100644 120000 aaaa aaaa link", "link", .modified),
        ("? untracked.txt", "untracked.txt", .untracked),
        ("! build/out.o", "build/out.o", .ignored),
        ("u UU N... 100644 100644 100644 100644 aaaa bbbb cccc both.swift", "both.swift", .conflicted),
        ("u AA N... 000000 100644 100644 100644 0000 bbbb cccc added-twice.swift", "added-twice.swift", .conflicted)
    ])
    func `each record kind maps to one file status`(record: String, path: String, status: FileStatus) {
        let snapshot = GitParsers.porcelainV2(Self.records([record]))
        #expect(snapshot.entries.map(\.path) == [path])
        #expect(snapshot.entries.map(\.status) == [status])
        #expect(snapshot.entries.allSatisfy { $0.originalPath == nil })
    }

    @Test(arguments: [
        ("1 .M N... 100644 100644 100644 aaaa aaaa a.swift", GitStatusCode.unmodified, GitStatusCode.modified),
        ("1 M. N... 100644 100644 100644 aaaa bbbb a.swift", .modified, .unmodified),
        ("1 MM N... 100644 100644 100644 aaaa bbbb a.swift", .modified, .modified),
        ("1 A. N... 000000 100644 100644 0000 bbbb a.swift", .added, .unmodified),
        ("1 AM N... 000000 100644 100644 0000 bbbb a.swift", .added, .modified),
        ("1 .D N... 100644 100644 000000 aaaa aaaa a.swift", .unmodified, .deleted),
        ("1 .T N... 100644 100644 120000 aaaa aaaa a.swift", .unmodified, .typeChanged),
        ("? a.swift", .unmodified, .untracked),
        ("! a.swift", .unmodified, .ignored),
        ("u UU N... 100644 100644 100644 100644 aaaa bbbb cccc a.swift", .unmerged, .unmerged),
        ("u AA N... 000000 100644 100644 100644 0000 bbbb cccc a.swift", .added, .added)
    ])
    func `each record keeps what changed in the index and in the working tree apart`(
        record: String, index: GitStatusCode, worktree: GitStatusCode
    ) throws {
        let entry = try #require(GitParsers.porcelainV2(Self.records([record])).entries.first)
        #expect(entry.path == "a.swift")
        #expect(entry.indexStatus == index)
        #expect(entry.worktreeStatus == worktree)
    }

    @Test(arguments: [
        ("2 R. N... 100644 100644 100644 aaaa aaaa R100 new.swift", GitStatusCode.renamed, GitStatusCode.unmodified),
        ("2 RM N... 100644 100644 100644 aaaa bbbb R100 new.swift", .renamed, .modified),
        ("2 C. N... 100644 100644 100644 aaaa aaaa C90 new.swift", .copied, .unmodified)
    ])
    func `a rename or copy record keeps its columns next to its original path`(
        record: String, index: GitStatusCode, worktree: GitStatusCode
    ) throws {
        let entry = try #require(GitParsers.porcelainV2(Self.records([record, "old.swift"])).entries.first)
        #expect(entry.path == "new.swift")
        #expect(entry.originalPath == "old.swift")
        #expect(entry.indexStatus == index)
        #expect(entry.worktreeStatus == worktree)
    }

    @Test
    func `a column letter git does not document reads as a modification and a missing one as unmodified`() throws {
        let entry = try #require(
            GitParsers.porcelainV2(Self.records(["1 X N... 100644 100644 100644 aaaa bbbb a.swift"])).entries.first)
        #expect(entry.indexStatus == .modified)
        #expect(entry.worktreeStatus == .unmodified)
        #expect(entry.status == .modified)
    }

    @Test
    func `a rename record carries the original path from the following field`() {
        let data = Self.records(["2 R. N... 100644 100644 100644 aaaa aaaa R100 new name.swift", "old name.swift"])
        let snapshot = GitParsers.porcelainV2(data)
        #expect(
            snapshot.entries == [
                GitStatusEntry(
                    path: "new name.swift", originalPath: "old name.swift", status: .renamed, indexStatus: .renamed,
                    worktreeStatus: .unmodified)
            ])
        let copy = Self.records(["2 C. N... 100644 100644 100644 aaaa aaaa C90 copy.swift", "source.swift"])
        #expect(GitParsers.porcelainV2(copy).entries.first?.status == .added)
        #expect(GitParsers.porcelainV2(copy).entries.first?.originalPath == "source.swift")
    }

    @Test
    func `a submodule record is marked as such`() {
        let data = Self.records(["1 .M SCM. 160000 160000 160000 aaaa aaaa vendor/lib"])
        let entry = GitParsers.porcelainV2(data).entries.first
        #expect(entry?.isSubmodule == true)
        #expect(entry?.status == .modified)
    }

    @Test
    func `paths keep spaces and unicode and records with too few fields are skipped`() {
        let data = Self.records([
            "1 .M N... 100644 100644 100644 aaaa bbbb dir with space/é.swift", "garbage", "1 short"
        ])
        let snapshot = GitParsers.porcelainV2(data)
        #expect(snapshot.entries.map(\.path) == ["dir with space/é.swift"])
    }

    @Test
    func `the summary counts each status once and the directory statuses take the most severe child`() {
        let data = Self.records([
            "1 .M N... 100644 100644 100644 aaaa bbbb src/a.swift",
            "1 A. N... 000000 100644 100644 0000 bbbb src/deep/b.swift",
            "u UU N... 100644 100644 100644 100644 aaaa bbbb cccc src/deep/c.swift",
            "? notes.txt"
        ])
        let snapshot = GitParsers.porcelainV2(data)
        #expect(snapshot.summary == FileStatusSummary(modified: 1, added: 1, untracked: 1, deleted: 0, conflicted: 1))
        let byPath = snapshot.statusesByPath(includingDirectories: true)
        #expect(byPath["src/deep/c.swift"] == .conflicted)
        #expect(byPath["src/deep"] == .conflicted)
        #expect(byPath["src"] == .conflicted)
        #expect(byPath["notes.txt"] == .untracked)
        #expect(byPath[""] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a real repository reports every kind of change`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "atelier-status-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        func git(_ arguments: String...) async throws {
            let spec = ProcessSpec(
                executable: GitClient.executable, arguments: ["-c", "user.name=t", "-c", "user.email=t@t"] + arguments,
                currentDirectory: root, environment: .inherited(overriding: GitClient.hardeningEnvironment))
            let output = try await runner.run(spec)
            try #require(output.succeeded, "\(output.errorText)")
        }
        func write(_ name: String, _ text: String) throws {
            try text.write(to: root.appending(path: name), atomically: true, encoding: .utf8)
        }
        try await git("init", "-q", "-b", "main")
        try write("kept.txt", "kept\n")
        try write("changed.txt", "one\n")
        try write("staged.txt", "one\n")
        try write("both.txt", "one\n")
        try write("removed.txt", "bye\n")
        try write("moved.txt", String(repeating: "same line\n", count: 20))
        try write(".gitignore", "ignored.txt\n")
        try await git("add", ".")
        try await git("commit", "-q", "-m", "base")
        try write("changed.txt", "two\n")
        try write("staged.txt", "two\n")
        try write("both.txt", "two\n")
        try write("added.txt", "new\n")
        try write("added-then-edited.txt", "new\n")
        try write("untracked.txt", "loose\n")
        try write("ignored.txt", "junk\n")
        try FileManager.default.removeItem(at: root.appending(path: "removed.txt"))
        try FileManager.default.moveItem(at: root.appending(path: "moved.txt"), to: root.appending(path: "renamed.txt"))
        try await git("add", "staged.txt", "both.txt", "added.txt", "added-then-edited.txt", "moved.txt", "renamed.txt")
        try write("both.txt", "three\n")
        try write("added-then-edited.txt", "newer\n")

        let client = GitClient(repository: root, runner: runner)
        let snapshot = try await client.status()

        #expect(snapshot.branch?.head == "main")
        let statuses = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.path, $0.status) })
        #expect(statuses["changed.txt"] == .modified)
        #expect(statuses["added.txt"] == .added)
        #expect(statuses["removed.txt"] == .deleted)
        #expect(statuses["renamed.txt"] == .renamed)
        #expect(snapshot.entries.first { $0.path == "renamed.txt" }?.originalPath == "moved.txt")
        #expect(statuses["untracked.txt"] == .untracked)
        #expect(statuses["ignored.txt"] == .ignored)
        #expect(statuses["kept.txt"] == nil)
        let columns = Dictionary(
            uniqueKeysWithValues: snapshot.entries.map { ($0.path, [$0.indexStatus, $0.worktreeStatus]) })
        #expect(columns["changed.txt"] == [.unmodified, .modified])
        #expect(columns["staged.txt"] == [.modified, .unmodified])
        #expect(columns["both.txt"] == [.modified, .modified])
        #expect(columns["added.txt"] == [.added, .unmodified])
        #expect(columns["added-then-edited.txt"] == [.added, .modified])
        #expect(columns["removed.txt"] == [.unmodified, .deleted])
        #expect(columns["renamed.txt"] == [.renamed, .unmodified])
        #expect(columns["untracked.txt"] == [.unmodified, .untracked])
        #expect(columns["ignored.txt"] == [.unmodified, .ignored])
    }
}
