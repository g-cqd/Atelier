import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// `GitClient`'s history checks: what they ask git for, and how they read its answer.
struct GitClientHistoryTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)

    private static func client(answering output: ProcessOutput) -> (GitClient, FakeProcessRunner) {
        let runner = FakeProcessRunner.gated(always: output)
        return (GitClient(repository: repository, runner: runner, gate: GitConfigGate()), runner)
    }

    // MARK: isAncestor

    @Test
    func `an ancestor is answered by exit status zero`() async throws {
        let (client, runner) = Self.client(answering: .success(""))

        #expect(try await client.isAncestor("main", of: "feature"))
        #expect(
            runner.commandSpecs.first?.arguments.suffix(5)
                == ["merge-base", "--is-ancestor", "--end-of-options", "main", "feature"])
    }

    @Test
    func `exit status one reads as not an ancestor, not as a failure`() async throws {
        let (client, _) = Self.client(answering: .failure(1, error: ""))

        #expect(try await client.isAncestor("feature", of: "main") == false)
    }

    @Test
    func `any other exit status of the ancestry check throws with git's message`() async {
        let (client, _) = Self.client(answering: .failure(128, error: "fatal: Not a valid object name nope\n"))

        await #expect(throws: GitError.commandFailed("fatal: Not a valid object name nope")) {
            try await client.isAncestor("nope", of: "main")
        }
    }

    @Test
    func `an option-shaped ref never reaches git`() async {
        let (client, runner) = Self.client(answering: .success(""))

        await #expect(throws: GitError.invalidArgument("--output=x")) {
            try await client.isAncestor("--output=x", of: "main")
        }
        await #expect(throws: GitError.invalidArgument("-p")) { try await client.mergeBase("main", "-p") }
        await #expect(throws: GitError.invalidArgument("--all")) {
            try await client.commitCount(from: "--all", to: "main", firstParent: true)
        }
        #expect(runner.specs.isEmpty)
    }

    // MARK: mergeBase

    @Test
    func `the merge base is the commit git prints`() async throws {
        let id = String(repeating: "a", count: 40)
        let (client, runner) = Self.client(answering: .success("\(id)\n"))

        #expect(try await client.mergeBase("main", "feature") == id)
        #expect(runner.commandSpecs.first?.arguments.suffix(4) == ["merge-base", "--end-of-options", "main", "feature"])
    }

    @Test
    func `histories with no common commit have no merge base`() async throws {
        let (client, _) = Self.client(answering: .failure(1, error: ""))

        #expect(try await client.mergeBase("main", "orphan") == nil)
    }

    @Test
    func `a merge base run that fails throws`() async {
        let (client, _) = Self.client(answering: .failure(128, error: "fatal: Not a valid object name nope\n"))

        await #expect(throws: GitError.commandFailed("fatal: Not a valid object name nope")) {
            try await client.mergeBase("main", "nope")
        }
    }

    // MARK: commitCount

    @Test
    func `the commit count walks the range, first parents only on request`() async throws {
        let (client, runner) = Self.client(answering: .success("42\n"))

        #expect(try await client.commitCount(from: "main", to: "feature", firstParent: true) == 42)
        #expect(try await client.commitCount(from: "main", to: "feature", firstParent: false) == 42)

        let arguments = runner.commandSpecs.map { Array($0.arguments.drop(while: { $0 != "rev-list" })) }
        #expect(
            arguments == [
                ["rev-list", "--count", "--first-parent", "--end-of-options", "main..feature"],
                ["rev-list", "--count", "--end-of-options", "main..feature"]
            ])
    }

    @Test
    func `a count git did not print throws`() async {
        let (client, _) = Self.client(answering: .success("many\n"))

        await #expect(throws: GitError.self) {
            try await client.commitCount(from: "main", to: "feature", firstParent: true)
        }
    }

    // MARK: Real git

    @Test
    func `real git answers ancestry, merge base and counts for a branch and an orphan`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "1\n")
        let base = try repository.commit("base")
        try repository.git("switch", "-q", "-c", "feature")
        try repository.write("a.txt", "2\n")
        try repository.commit("feature one")
        try repository.write("b.txt", "b\n")
        let feature = try repository.commit("feature two")
        try repository.git("switch", "-q", "main")
        try repository.write("c.txt", "c\n")
        let main = try repository.commit("main one")
        try repository.git("switch", "-q", "--orphan", "orphan")
        let orphan = try repository.commit("unrelated", allowingEmpty: true)
        let client = repository.client()

        #expect(try await client.isAncestor(base, of: feature))
        #expect(try await client.isAncestor(feature, of: feature))
        #expect(try await client.isAncestor(feature, of: base) == false)
        #expect(try await client.isAncestor(main, of: feature) == false)
        #expect(try await client.mergeBase(main, feature) == base)
        #expect(try await client.mergeBase(main, orphan) == nil)
        #expect(try await client.commitCount(from: base, to: feature, firstParent: true) == 2)
        #expect(try await client.commitCount(from: feature, to: base, firstParent: false) == 0)
    }

    // MARK: commitChanges

    @Test
    func `the listing asks git for one page of the range with the pinned configuration`() async throws {
        let (client, runner) = Self.client(answering: .success(""))

        _ = try await client.commitChanges(from: "main", to: "feature", firstParent: true, limit: 200)

        let spec = try #require(runner.commandSpecs.first)
        #expect(spec.arguments.starts(with: GitIsolation.strictConfigurationFlags))
        #expect(spec.arguments.contains("diff.autoRefreshIndex=false"))
        #expect(spec.environment == GitIsolation.strict.environment)
        #expect(
            Array(spec.arguments.drop(while: { $0 != "log" }))
                == [
                    "log", "--no-show-signature", "--no-ext-diff", "--no-textconv", "--no-color", "--no-relative",
                    "--no-abbrev", "--root", "--raw", "-M", "-z", GitParsers.commitChangesFormat, "--first-parent",
                    "--diff-merges=first-parent", "-n", "200", "--end-of-options", "main..feature", "--"
                ])
    }

    @Test
    func `a page of no commits, or of a bad size, never reaches git`() async {
        let (client, runner) = Self.client(answering: .success(""))

        await #expect(throws: GitError.self) {
            try await client.commitChanges(from: "main", to: "feature", firstParent: true, limit: 0)
        }
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `real git lists a merge along first parents with everything it brought in`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "1\n")
        let base = try repository.commit("base")
        try repository.git("switch", "-q", "-c", "feature")
        try repository.write("f1.txt", "1\n")
        try repository.commit("feature one")
        try repository.write("f2.txt", "2\n")
        try repository.commit("feature two")
        try repository.git("switch", "-q", "main")
        try repository.write("a.txt", "2\n")
        let mainline = try repository.commit("main one")
        try repository.git("merge", "-q", "--no-ff", "-m", "Merge feature", "feature")
        let merge = try repository.head()
        let client = repository.client()

        let firstParents = try await client.commitChanges(from: base, to: merge, firstParent: true, limit: 10)
        let every = try await client.commitChanges(from: base, to: merge, firstParent: false, limit: 10)

        #expect(firstParents.commits.map(\.subject) == ["Merge feature", "main one"])
        #expect(firstParents.commits.first?.isMerge == true)
        #expect(firstParents.commits.first?.parentIDs.first == mainline)
        #expect(firstParents.commits.first?.changes.map(\.path).sorted() == ["f1.txt", "f2.txt"])
        #expect(firstParents.commits.last?.authorName == "Tess Ter")
        #expect(firstParents.isComplete && firstParents.continuation == nil)
        #expect(every.commits.count == 4)
        #expect(every.commits.first { $0.isMerge }?.changes.isEmpty == true)
    }

    @Test
    func `real git follows a file renamed twice, one commit at a time`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a file long enough to be recognized after a move\n")
        let base = try repository.commit("base")
        try repository.git("mv", "a.txt", "b.txt")
        try repository.commit("first move")
        try FileManager.default.createDirectory(
            at: repository.root.appending(path: "dir"), withIntermediateDirectories: true)
        try repository.git("mv", "b.txt", "dir/c d.txt")
        let tip = try repository.commit("second move")

        let page = try await repository.client().commitChanges(from: base, to: tip, firstParent: true, limit: 10)

        #expect(page.commits.map { $0.changes.map(\.status) } == [[.renamed], [.renamed]])
        #expect(page.commits.map { $0.changes.first?.oldPath } == ["b.txt", "a.txt"])
        #expect(page.commits.map { $0.changes.first?.path } == ["dir/c d.txt", "b.txt"])
    }

    @Test
    func `real git lists a file changed then changed back under both commits`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "1\n")
        let base = try repository.commit("base")
        try repository.write("a.txt", "2\n")
        try repository.commit("change")
        try repository.write("a.txt", "1\n")
        let tip = try repository.commit("change back")

        let page = try await repository.client().commitChanges(from: base, to: tip, firstParent: true, limit: 10)

        #expect(page.commits.map(\.subject) == ["change back", "change"])
        #expect(page.commits.map { $0.changes.map(\.path) } == [["a.txt"], ["a.txt"]])
        #expect(page.commits[0].changes[0].newBlobID == page.commits[1].changes[0].oldBlobID)
    }

    @Test
    func `real git pages continue from the first parent of the oldest commit listed`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("n.txt", "0\n")
        let base = try repository.commit("base")
        for step in 1 ... 5 {
            try repository.write("n.txt", "\(step)\n")
            try repository.commit("step \(step)")
        }
        let tip = try repository.head()
        let client = repository.client()

        let whole = try await client.commitChanges(from: base, to: tip, firstParent: true, limit: 10)
        var pages: [GitCommitPage] = []
        var next: String? = tip
        while let page = next {
            let listed = try await client.commitChanges(from: base, to: page, firstParent: true, limit: 2)
            pages.append(listed)
            next = listed.continuation
        }

        #expect(pages.flatMap(\.commits) == whole.commits)
        #expect(pages.map(\.commits.count) == [2, 2, 1])
        #expect(pages.map(\.isComplete) == [false, false, true])
        #expect(pages.first?.continuation == whole.commits[2].id)
    }

    // MARK: uncommittedChanges

    @Test
    func `real git lists staged, unstaged and renamed files, then untracked ones as additions`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write(".gitignore", "build/\n")
        try repository.write("staged.txt", "1\n")
        try repository.write("unstaged.txt", "1\n")
        try repository.write("moved.txt", "a file long enough to be recognized after a move\n")
        try repository.commit("base")
        try repository.write("staged.txt", "2\n")
        try repository.git("add", "staged.txt")
        try repository.write("unstaged.txt", "2\n")
        try repository.git("mv", "moved.txt", "renamed.txt")
        try repository.write("new file.txt", "new\n")
        try repository.write("build/out.o", "ignored\n")

        let changes = try await repository.client().uncommittedChanges()

        let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) })
        #expect(Set(byPath.keys) == ["staged.txt", "unstaged.txt", "renamed.txt", "new file.txt"])
        #expect(byPath["staged.txt"]?.status == .modified)
        #expect(byPath["unstaged.txt"]?.status == .modified)
        #expect(byPath["renamed.txt"]?.status == .renamed)
        #expect(byPath["renamed.txt"]?.oldPath == "moved.txt")
        #expect(byPath["new file.txt"]?.status == .added)
        #expect(changes.last?.path == "new file.txt")
    }

    @Test
    func `uncommitted changes read the working tree against HEAD and the untracked files`() async throws {
        let runner = FakeProcessRunner.gated(ordinaryRepositoryLines) { spec in
            spec.arguments.contains("ls-files") ? .success("u.txt\u{0}") : .success("")
        }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        #expect(try await client.uncommittedChanges() == [GitFileChange(status: .added, path: "u.txt")])
        let diff = try #require(runner.commandSpecs.first { $0.arguments.contains("diff") })
        #expect(diff.arguments.suffix(4) == ["-z", "--end-of-options", "HEAD", "--"])
        #expect(diff.arguments.contains("diff.autoRefreshIndex=false"))
    }
}
