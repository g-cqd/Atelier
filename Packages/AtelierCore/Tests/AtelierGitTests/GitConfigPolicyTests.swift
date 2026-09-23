import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierGit

/// ``GitConfigPolicy``: how a repository's own configuration is read, which keys it may hold, and which fetch URLs
/// a command may reach.
struct GitConfigPolicyTests {
    private static let directory = URL(filePath: "/repo", directoryHint: .isDirectory)

    @Test
    func `a listing splits into scope, origin, key and value`() throws {
        let listing = gitConfigListing([
            GitConfigLine(.system, "credential.helper", "osxkeychain", file: "/etc/gitconfig"),
            GitConfigLine(.local, "core.bare", "false", file: ".git/config"),
            GitConfigLine(.local, "core.bare", nil, file: ".git/config"),
            GitConfigLine(.worktree, "weird.a.b c.v", "line1\nline2", file: ".git/config.worktree")
        ])

        let entries = try #require(GitConfigPolicy.entries(inListing: Data(listing.utf8), relativeTo: Self.directory))

        #expect(entries.map(\.scope) == [.system, .local, .local, .worktree])
        #expect(entries[0].file == "/etc/gitconfig")
        #expect(entries[1].value == "false")
        // A key written with no value at all is printed without its newline.
        #expect(entries[2].value == nil)
        // Only the first newline separates the key from a value that holds newlines of its own.
        #expect(entries[3].key == "weird.a.b c.v")
        #expect(entries[3].value == "line1\nline2")
    }

    @Test
    func `a repository's own origins are resolved against the directory git ran in`() throws {
        let listing = gitConfigListing([GitConfigLine(.local, "core.bare", "false", file: ".git/config")])

        let entries = try #require(GitConfigPolicy.entries(inListing: Data(listing.utf8), relativeTo: Self.directory))

        #expect(entries[0].file == "/repo/.git/config")
    }

    @Test
    func `a truncated listing is not parsed at all`() {
        // Two fields instead of three: the scope and the origin of an entry whose key never arrived.
        #expect(
            GitConfigPolicy.entries(inListing: Data("local\0file:.git/config\0".utf8), relativeTo: Self.directory)
                == nil)
    }

    @Test(arguments: [
        "filter.x.clean", "filter.lfs.process", "diff.evil.command", "diff.evil.textconv", "diff.external",
        "gpg.program", "gpg.ssh.program", "gpg.x509.program", "log.showsignature", "core.askpass", "core.gitproxy",
        "core.worktree", "core.alternaterefscommand", "core.excludesfile", "core.attributesfile",
        "credential.helper", "credential.https://x.example.com.helper", "remote.origin.uploadpack",
        "remote.origin.receivepack", "remote.origin.vcs", "remote.origin.proxy", "protocol.ext.allow",
        "protocol.allow", "include.path", "includeif.gitdir:/x/.path", "url.ext::sh -c x.insteadof",
        "submodule.sub.update", "alias.st", "pager.diff", "sequence.editor", "hook.pre-commit.command",
        "interactive.difffilter", "trailer.sign.command", "merge.evil.driver", "mergetool.evil.cmd",
        "gc.recentobjectshook"
    ])
    func `a key that can make git run a command is refused`(key: String) {
        #expect(!GitConfigPolicy.isInert(key), "\(key) must not be inert")
    }

    @Test(arguments: [
        "core.repositoryformatversion", "core.filemode", "core.bare", "core.logallrefupdates", "core.ignorecase",
        "core.precomposeunicode", "core.autocrlf", "core.sparsecheckout", "core.hookspath", "core.fsmonitor",
        "core.pager", "core.editor", "core.sshcommand", "remote.origin.url", "remote.origin.fetch",
        "remote.origin.pushurl", "remote.origin.gh-resolved", "branch.main.remote", "branch.main.merge",
        "branch.main.vscode-merge-base", "branch.main.github-pr-owner-number", "rerere.enabled", "user.email",
        "commit.gpgsign", "push.default", "status.showuntrackedfiles", "extensions.worktreeconfig",
        "submodule.sub.url", "submodule.sub.active", "init.defaultbranch", "diff.algorithm", "log.date"
    ])
    func `a key an ordinary checkout holds is inert`(key: String) {
        #expect(GitConfigPolicy.isInert(key), "\(key) must stay inert")
    }

    @Test
    func `a key from an unknown section is refused, because the allowlist decides`() {
        #expect(!GitConfigPolicy.isInert("somethingnew.key"))
        #expect(!GitConfigPolicy.isInert("guitool.evil.cmd"))
    }

    @Test
    func `only the repository's own scopes are judged`() throws {
        let listing = gitConfigListing([
            GitConfigLine(.global, "filter.lfs.clean", "git-lfs clean -- %f"),
            GitConfigLine(.system, "credential.helper", "osxkeychain"),
            GitConfigLine(.unknown, "gpg.program", "/usr/bin/gpg"),
            GitConfigLine(.command, "protocol.ext.allow", "never"),
            GitConfigLine(.local, "core.bare", "false")
        ])
        let entries = try #require(GitConfigPolicy.entries(inListing: Data(listing.utf8), relativeTo: Self.directory))

        let verdict = GitConfigPolicy.verdict(for: entries)

        #expect(verdict.isApproved)
        // The user's own global filter driver keeps working; blanking it would break every git-lfs checkout.
        #expect(verdict.filterDrivers.isEmpty)
        #expect(verdict.entries.map(\.key) == ["core.bare"])
    }

    @Test
    func `an included file's keys are judged, because git reports them under the scope that included them`() throws {
        let listing = gitConfigListing([
            GitConfigLine(.local, "include.path", "../payload.cfg", file: ".git/config"),
            GitConfigLine(.local, "filter.x.clean", "sh -c touch /tmp/marker", file: ".git/../payload.cfg")
        ])
        let entries = try #require(GitConfigPolicy.entries(inListing: Data(listing.utf8), relativeTo: Self.directory))

        let verdict = GitConfigPolicy.verdict(for: entries)

        #expect(verdict.refusedKeys == ["include.path", "filter.x.clean"])
        #expect(verdict.files == ["/repo/.git/../payload.cfg", "/repo/.git/config"])
    }

    @Test
    func `the verdict keeps the filter drivers and the user's credential helpers`() throws {
        let listing = gitConfigListing([
            GitConfigLine(.system, "credential.helper", "osxkeychain"),
            GitConfigLine(.global, "credential.helper", "cache --timeout=60"),
            GitConfigLine(.local, "filter.a.clean", "payload"),
            GitConfigLine(.local, "filter.a.smudge", "payload"),
            GitConfigLine(.local, "filter.b.process", "payload")
        ])
        let entries = try #require(GitConfigPolicy.entries(inListing: Data(listing.utf8), relativeTo: Self.directory))

        let verdict = GitConfigPolicy.verdict(for: entries)

        #expect(verdict.filterDrivers == ["a", "b"])
        #expect(verdict.userCredentialHelpers == ["osxkeychain", "cache --timeout=60"])
    }

    @Test
    func `blanking flags cover both filter paths and the required flag`() {
        let flags = GitConfigPolicy.filterBlankingFlags(for: ["x"])

        #expect(
            flags == [
                "-c", "filter.x.clean=", "-c", "filter.x.smudge=", "-c", "filter.x.process=",
                "-c", "filter.x.required=false"
            ])
    }

    @Test(arguments: [
        "https://example.com/a.git", "ssh://git@example.com/a.git", "git@github.com:aemi/atelier.git",
        "HTTPS://example.com/a.git", "user@host:path"
    ])
    func `an https or ssh remote may be fetched from`(url: String) {
        #expect(GitConfigPolicy.transportURL(url) == url)
    }

    @Test(arguments: [
        "ext::sh -c 'touch /tmp/marker'", "git://example.com/a.git", "http://example.com/a.git",
        "file:///tmp/repo", "/tmp/repo", "./repo", "../repo", "", "-upload-pack=payload",
        "ssh://-oProxyCommand=payload@host/a.git", "https:///a.git", "transport::address", "a.git"
    ])
    func `any other remote is refused before a fetch runs`(url: String) {
        #expect(GitConfigPolicy.transportURL(url) == nil, "\(url) must not be fetched from")
    }

    @Test
    func `a redacted URL keeps the host and drops the credentials`() {
        #expect(GitConfigPolicy.redacted("https://user:token@example.com/a.git") == "https://example.com/a.git")
        #expect(GitConfigPolicy.redacted("git@github.com:aemi/atelier.git") == "github.com:aemi/atelier.git")
        #expect(GitConfigPolicy.redacted("https://example.com/a.git") == "https://example.com/a.git")
    }
}

/// ``GitConfigGate``: one read per configuration change, not one per command.
struct GitConfigGateTests {
    /// A directory holding a real `.git/config`, so the gate's stamps have a file to watch.
    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "atelier-gate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: ".git", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try "[core]\n\tbare = false\n".write(to: root.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        return root
    }

    private func listing(for root: URL) -> Data {
        Data(
            gitConfigListing([
                GitConfigLine(.local, "core.bare", "false", file: root.appending(path: ".git/config").path)
            ])
            .utf8)
    }

    @Test
    func `a second command reuses the verdict instead of reading the configuration again`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()

        for _ in 0 ..< 3 {
            _ = await gate.verdict(in: root, isolation: .strict) {
                reads.record(())
                return listing(for: root)
            }
        }

        #expect(reads.count == 1)
    }

    @Test
    func `editing a configuration file drops the cached verdict`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()
        _ = await gate.verdict(in: root, isolation: .strict) {
            reads.record(())
            return listing(for: root)
        }

        try "[core]\n\tbare = false\n[filter \"x\"]\n\tclean = payload\n"
            .write(to: root.appending(path: ".git/config"), atomically: true, encoding: .utf8)
        _ = await gate.verdict(in: root, isolation: .strict) {
            reads.record(())
            return listing(for: root)
        }

        #expect(reads.count == 2)
    }

    @Test
    func `a configuration file appearing beside the one read drops the cached verdict`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()
        _ = await gate.verdict(in: root, isolation: .strict) {
            reads.record(())
            return listing(for: root)
        }

        // `config.worktree` was not in the listing, so only the directory's own modification date can show it.
        try "[filter \"x\"]\n\tclean = payload\n"
            .write(to: root.appending(path: ".git/config.worktree"), atomically: true, encoding: .utf8)
        _ = await gate.verdict(in: root, isolation: .strict) {
            reads.record(())
            return listing(for: root)
        }

        #expect(reads.count == 2)
    }

    @Test
    func `a strict verdict is never reused for a fetch, which reads the system scope too`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()

        for isolation in [GitIsolation.strict, .networking, .strict, .networking] {
            _ = await gate.verdict(in: root, isolation: isolation) {
                reads.record(())
                return listing(for: root)
            }
        }

        #expect(reads.count == 2)
    }

    @Test
    func `a directory with no repository configuration is never cached`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()
        let global = Data(gitConfigListing([GitConfigLine(.global, "user.email", "t@t")]).utf8)

        for _ in 0 ..< 2 {
            _ = await gate.verdict(in: root, isolation: .strict) {
                reads.record(())
                return global
            }
        }

        #expect(reads.count == 2)
    }

    @Test
    func `the cache holds no more repositories than its capacity`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate(capacity: 1)
        let reads = AsyncEventProbe<Void>()
        let other = root.appending(path: "other", directoryHint: .isDirectory)

        for directory in [root, other, root] {
            _ = await gate.verdict(in: directory, isolation: .strict) {
                reads.record(())
                return listing(for: root)
            }
        }

        #expect(reads.count == 3)
    }

    @Test
    func `output that cannot be parsed refuses the repository and is not cached`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = GitConfigGate()
        let reads = AsyncEventProbe<Void>()

        var verdicts: [GitConfigVerdict] = []
        for _ in 0 ..< 2 {
            verdicts.append(
                await gate.verdict(in: root, isolation: .strict) {
                    reads.record(())
                    return Data("local\0file:.git/config\0".utf8)
                })
        }

        #expect(verdicts.allSatisfy { !$0.isApproved })
        #expect(verdicts[0].refusedKeys == [GitConfigGate.unreadableConfiguration])
        #expect(reads.count == 2)
    }
}
