import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// What the configuration gate and the pins put on a git command line, and what a refused repository gets instead.
struct GitClientGateTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)

    @Test
    func `fetch goes to the remote's URL with the remote's own refspec, never to its name`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        let spec = try #require(runner.commandSpecs.first)
        #expect(
            spec.arguments.suffix(4)
                == [
                    "fetch", "--no-recurse-submodules", "--end-of-options", "git@github.com:aemi/atelier.git",
                    "+refs/heads/*:refs/remotes/origin/*"
                ]
                .suffix(4))
        #expect(spec.arguments.last == "+refs/heads/*:refs/remotes/origin/*")
        #expect(!spec.arguments.contains("--prune"))
        #expect(!spec.arguments.contains("origin"))
    }

    @Test
    func `a remote with no configured refspec falls back to the default one`() async throws {
        let lines = ordinaryRepositoryLines.filter { $0.key != "remote.origin.fetch" }
        let runner = FakeProcessRunner.gated(lines) { _ in .success("") }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        #expect(runner.commandSpecs.first?.arguments.last == "+refs/heads/*:refs/remotes/origin/*")
    }

    @Test
    func `a remote whose URL is neither https nor ssh is never fetched from`() async throws {
        let lines =
            ordinaryRepositoryLines.filter { $0.key != "remote.origin.url" }
            + [GitConfigLine(.local, "remote.origin.url", "ext::sh -c payload")]
        let runner = FakeProcessRunner.gated(lines) { _ in .success("") }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.unsupportedRemoteURL("ext::sh -c payload")) { try await client.fetch() }
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `a remote the repository never defined is refused by name`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        await #expect(throws: GitError.unsupportedRemoteURL("upstream has no URL")) {
            try await client.fetch(remote: "upstream")
        }
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `the pins put the user's own credential helpers back after resetting the list`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        let arguments = try #require(runner.commandSpecs.first).arguments
        let reset = try #require(arguments.firstIndex(of: "credential.helper="))
        let restored = try #require(arguments.firstIndex(of: "credential.helper=osxkeychain"))
        // Order decides: git clears the list at the empty value, so the user's helper has to come after it.
        #expect(reset < restored)
    }
    @Test(arguments: [
        "protocol.allow=never", "protocol.ext.allow=never", "protocol.file.allow=never",
        "protocol.https.allow=always", "protocol.ssh.allow=always", "credential.helper=", "core.askPass=",
        "core.gitProxy=", "gpg.program=false", "gpg.ssh.program=false", "gpg.x509.program=false"
    ])
    func `every fetch pin the verifier asked for reaches the argv`(pin: String) async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        try await client.fetch()
        #expect(try #require(runner.commandSpecs.first).arguments.contains(pin))
    }

    @Test(arguments: [
        "protocol.allow=never", "protocol.ext.allow=never", "protocol.file.allow=never", "gpg.program=false",
        "gpg.ssh.program=false", "gpg.x509.program=false", "core.sshCommand=/usr/bin/false", "core.fsmonitor=false",
        "core.hooksPath=/dev/null", "diff.external=", "core.pager=cat", "core.editor=false",
        "uploadpack.packObjectsHook=", "diff.autoRefreshIndex=false"
    ])
    func `every read pin reaches the argv`(pin: String) async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())
        _ = try await client.status()
        #expect(try #require(runner.commandSpecs.first).arguments.contains(pin))
    }

    @Test
    func `the commands that used to run a repository's programs carry their own guards`() async throws {
        let runner = FakeProcessRunner.gated(always: .success(""))
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        _ = try await client.status()
        _ = try await client.renames(from: "HEAD", to: nil)
        _ = try? await client.info()

        let arguments = runner.commandSpecs.map(\.arguments)
        let status = try #require(arguments.first { $0.contains("status") })
        #expect(status.contains("--ignore-submodules=dirty"))
        let diff = try #require(arguments.first { $0.contains("diff") })
        #expect(diff.contains("--no-ext-diff") && diff.contains("--no-textconv"))
        #expect(diff.contains("--ignore-submodules=dirty"))
        let log = try #require(arguments.first { $0.contains("log") })
        #expect(log.contains("--no-show-signature"))
    }

    @Test
    func `a repository that defines a filter driver has it blanked on every command`() async throws {
        let lines = ordinaryRepositoryLines + [GitConfigLine(.local, "filter.x.clean", "payload")]
        let runner = FakeProcessRunner.gated(lines) { _ in .success("") }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        // The gate refuses the repository outright; the blanking flags are the layer under it.
        await #expect(throws: GitError.refusedConfiguration(["filter.x.clean"])) { _ = try await client.status() }
        #expect(runner.commandSpecs.isEmpty)
        #expect(
            GitClient.mitigationFlags(
                for: GitConfigPolicy.verdict(
                    for: try #require(
                        GitConfigPolicy.entries(
                            inListing: Data(gitConfigListing(lines).utf8), relativeTo: Self.repository))),
                isolation: .strict)
                == [
                    "-c", "filter.x.clean=", "-c", "filter.x.smudge=", "-c", "filter.x.process=", "-c",
                    "filter.x.required=false"
                ])
    }

    @Test
    func `a refused repository runs no command at all`() async throws {
        let lines = ordinaryRepositoryLines + [GitConfigLine(.local, "core.askpass", "payload")]
        let runner = FakeProcessRunner.gated(lines) { _ in .success("") }
        let client = GitClient(repository: Self.repository, runner: runner, gate: GitConfigGate())

        await #expect(throws: GitError.refusedConfiguration(["core.askpass"])) { _ = try await client.status() }
        await #expect(throws: GitError.self) { _ = try await client.workingTreePaths() }
        await #expect(throws: GitError.self) { _ = try await client.resolve(ref: "HEAD") }
        await #expect(throws: GitError.self) { _ = try await client.blobs(["abc"]) }
        await #expect(throws: GitError.self) { try await client.fetch() }

        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `the refusal names the keys and never their values`() {
        let message = GitError.refusedConfiguration(["filter.x.clean", "core.gitproxy"]).errorDescription

        #expect(message?.contains("filter.x.clean") == true)
        #expect(message?.contains("core.gitproxy") == true)
        #expect(message?.contains("payload") == false)
    }
}
