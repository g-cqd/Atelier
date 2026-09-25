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
}
