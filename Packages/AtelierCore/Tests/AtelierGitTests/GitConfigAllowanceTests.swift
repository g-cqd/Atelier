import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// The keys a user allows in one repository despite ``GitConfigPolicy``'s allowlist, and the refusal that names them.
struct GitConfigAllowanceTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
    private static let toolKey = "project-hooks.trusted"

    @Test
    func `an allowed key is not refused`() {
        let entries = [GitConfigEntry(scope: .local, file: "/repo/.git/config", key: Self.toolKey, value: "true")]

        #expect(GitConfigPolicy.verdict(for: entries).refusedKeys == [Self.toolKey])
        #expect(GitConfigPolicy.verdict(for: entries, allowing: [Self.toolKey]).isApproved)
    }

    @Test(arguments: ["filter.x.clean", "core.askpass", "credential.helper", "include.path", "diff.x.textconv"])
    func `a key that names a program stays refused when allowed`(key: String) {
        let entries = [GitConfigEntry(scope: .local, file: "/repo/.git/config", key: key, value: "x")]

        #expect(!GitConfigPolicy.canBeAllowed(key))
        #expect(GitConfigPolicy.verdict(for: entries, allowing: [key]).refusedKeys == [key])
    }

    @Test
    func `an allowance lets git run in a repository it would refuse`() async throws {
        let gate = GitConfigGate()
        let client = GitClient(repository: Self.repository, runner: Self.runnerWithToolKey(), gate: gate)
        await #expect(throws: GitError.refusedConfiguration([Self.toolKey])) { try await client.resolve(ref: "HEAD") }

        gate.allow([Self.toolKey], inRepository: Self.repository)

        _ = try await client.resolve(ref: "HEAD")
    }

    @Test
    func `an allowance covers a directory inside the repository`() async throws {
        let gate = GitConfigGate()
        gate.allow([Self.toolKey], inRepository: Self.repository)
        let inside = Self.repository.appending(path: "Sources/App", directoryHint: .isDirectory)

        let root = await GitClient.repositoryRoot(containing: inside, runner: Self.runnerWithToolKey(), gate: gate)

        #expect(root != nil)
    }

    @Test
    func `an allowance for another repository does not apply`() async {
        let gate = GitConfigGate()
        gate.allow([Self.toolKey], inRepository: URL(filePath: "/other", directoryHint: .isDirectory))
        let client = GitClient(repository: Self.repository, runner: Self.runnerWithToolKey(), gate: gate)

        await #expect(throws: GitError.refusedConfiguration([Self.toolKey])) { try await client.resolve(ref: "HEAD") }
    }

    @Test
    func `removing an allowance refuses the repository again`() async throws {
        let gate = GitConfigGate()
        let client = GitClient(repository: Self.repository, runner: Self.runnerWithToolKey(), gate: gate)
        gate.allow([Self.toolKey], inRepository: Self.repository)
        _ = try await client.resolve(ref: "HEAD")

        gate.allow([], inRepository: Self.repository)

        await #expect(throws: GitError.refusedConfiguration([Self.toolKey])) { try await client.resolve(ref: "HEAD") }
    }

    @Test
    func `a refusal names the repository root and its refused keys`() async throws {
        let root = try Self.makeRepositoryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = root.appending(path: "Sources", directoryHint: .isDirectory)

        let refusal = await GitClient.configurationRefusal(
            containing: inside,
            runner: Self.runnerWithToolKey(),
            gate: GitConfigGate()
        )

        #expect(refusal?.root.path(percentEncoded: false) == root.path(percentEncoded: false))
        #expect(refusal?.keys == [Self.toolKey])
        #expect(refusal?.allowableKeys == [Self.toolKey])
    }

    @Test
    func `an approved repository has no refusal`() async throws {
        let root = try Self.makeRepositoryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let refusal = await GitClient.configurationRefusal(
            containing: root,
            runner: FakeProcessRunner.gated(always: .success("")),
            gate: GitConfigGate()
        )

        #expect(refusal == nil)
    }

    private static func runnerWithToolKey() -> FakeProcessRunner {
        FakeProcessRunner.gated(ordinaryRepositoryLines + [GitConfigLine(.local, toolKey, "true")]) { _ in
            .success("/repo\n")
        }
    }

    /// A temporary folder holding an empty `.git` folder, which is all the refusal looks for.
    private static func makeRepositoryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "GitConfigAllowanceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        return root
    }
}
