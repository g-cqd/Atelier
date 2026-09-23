import AemiRuntime
import AemiTestKit
import AtelierProcess
import Foundation
import Testing

@testable import AtelierGit

/// The verifier's hostile-repository lab, rebuilt per test against the git on this machine: each vector plants a
/// payload that leaves a marker file, runs the command that used to start it, and checks that no marker appeared.
///
/// Every payload is a script that runs `touch`; nothing here reaches the network or writes outside its own
/// temporary directory.
@Suite(.serialized)
struct GitHostileRepositoryTests {
    // MARK: - Sec C2: read commands

    @Test
    func `a filter driver selected by the repository's own attributes never runs during status`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("config", "filter.x.clean", lab.payload("filter-status"))
        try lab.write(".git/info/attributes", "* filter=x\n")
        try lab.ageWorkingTree()

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().status() })

        #expect(error.refusedKeys == ["filter.x.clean"])
        #expect(!lab.markerExists("filter-status"))
    }

    @Test
    func `a filter driver never runs during the working-tree rename diff`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("config", "filter.x.clean", lab.payload("filter-diff"))
        try lab.write(".git/info/attributes", "* filter=x\n")
        try lab.ageWorkingTree()

        await #expect(throws: GitError.self) { try await lab.client().renames(from: "HEAD", to: nil) }

        #expect(!lab.markerExists("filter-diff"))
    }

    @Test
    func `a signature program never runs while the commits are read`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.commitSignedHead()
        try lab.git("config", "log.showSignature", "true")
        try lab.git("config", "gpg.program", lab.payload("gpg"))

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().info() })

        #expect(error.refusedKeys.sorted() == ["gpg.program", "log.showsignature"])
        #expect(!lab.markerExists("gpg"))
    }

    @Test
    func `a configuration file pulled in by include is judged like the repository's own`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let included = lab.directory.file("payload.cfg")
        try "[filter \"x\"]\n\tclean = \(try lab.payload("include"))\n"
            .write(toFile: included, atomically: true, encoding: .utf8)
        try lab.git("config", "include.path", included)
        try lab.write(".git/info/attributes", "* filter=x\n")
        try lab.ageWorkingTree()

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().status() })

        #expect(error.refusedKeys.contains("filter.x.clean"))
        #expect(!lab.markerExists("include"))
    }

    // MARK: - Sec H1: fetch

    @Test
    func `a remote that names its own uploadpack is never fetched from`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", lab.root.path)
        try lab.git("config", "remote.origin.uploadpack", lab.payload("uploadpack"))

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        #expect(error.refusedKeys == ["remote.origin.uploadpack"])
        #expect(!lab.markerExists("uploadpack"))
    }

    @Test
    func `an ext URL with the repository's own protocol allowance is never fetched from`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", "ext::\(try lab.payload("ext"))")
        try lab.git("config", "protocol.ext.allow", "always")

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        #expect(error.refusedKeys == ["protocol.ext.allow"])
        #expect(!lab.markerExists("ext"))
    }

    @Test
    func `a git proxy command never runs`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", "git://127.0.0.1:9/repo.git")
        try lab.git("config", "core.gitProxy", lab.payload("gitproxy"))

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        #expect(error.refusedKeys == ["core.gitproxy"])
        #expect(!lab.markerExists("gitproxy"))
    }

    @Test
    func `a credential helper the repository chose never runs`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", "https://127.0.0.1:9/repo.git")
        try lab.git("config", "credential.helper", "!\(try lab.payload("credential"))")

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        #expect(error.refusedKeys == ["credential.helper"])
        #expect(!lab.markerExists("credential"))
    }

    @Test
    func `an insteadOf rewrite of the fetch URL never runs`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", "https://example.invalid/repo.git")
        try lab.git("config", "url.ext::\(try lab.payload("insteadof")) .insteadOf", "https://example.invalid/")

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        #expect(error.refusedKeys.contains { $0.hasPrefix("url.") })
        #expect(!lab.markerExists("insteadof"))
    }

    @Test
    func `a local-path remote is refused even when every key is inert`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("remote", "add", "origin", lab.root.path)

        let error = try #require(await #expect(throws: GitError.self) { try await lab.client().fetch() })

        guard case .unsupportedRemoteURL = error else {
            Issue.record("expected the remote URL to be refused, got \(error)")
            return
        }
    }

    // MARK: - What still has to work

    @Test
    func `a checkout holding only ordinary keys still reports its status`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        try lab.git("config", "core.hooksPath", ".husky/_")
        try lab.git("config", "branch.main.vscode-merge-base", "origin/main")
        try lab.git("config", "remote.origin.gh-resolved", "base")
        try lab.git("config", "rerere.enabled", "true")
        try lab.git("remote", "add", "origin", "git@github.com:aemi/atelier.git")
        try lab.write("b.txt", "new\n")

        let snapshot = try await lab.client().status()

        #expect(snapshot.branch?.head == "main")
        #expect(snapshot.entries.contains { $0.path == "b.txt" && $0.status == .untracked })
    }

    @Test
    func `a hook the repository points at never runs, because the pin wins over its configuration`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let hooks = lab.directory.file("hooks")
        try FileManager.default.createDirectory(atPath: hooks, withIntermediateDirectories: true)
        for hook in ["post-index-change", "pre-auto-gc", "reference-transaction"] {
            try lab.script(at: "\(hooks)/\(hook)", touching: lab.marker("hook"))
        }
        try lab.git("config", "core.hooksPath", hooks)
        try lab.ageWorkingTree()

        _ = try await lab.client().status()

        #expect(!lab.markerExists("hook"))
    }

    @Test
    func `a submodule's own configuration cannot run a filter through the superproject's status`() async throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let source = try Lab()
        defer { source.cleanup() }
        try lab.git("submodule", "add", "-q", "--name", "sub", source.root.path, "sub")
        try lab.git("commit", "-q", "-m", "sub")
        let submoduleGitDir = lab.root.appending(path: ".git/modules/sub", directoryHint: .isDirectory)
        try lab.git("--git-dir=\(submoduleGitDir.path())", "config", "filter.x.clean", lab.payload("submodule"))
        let info = submoduleGitDir.appending(path: "info", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
        try "* filter=x\n".write(to: info.appending(path: "attributes"), atomically: true, encoding: .utf8)
        try lab.age(lab.root.appending(path: "sub/a.txt").path)

        _ = try await lab.client().status()
        _ = try await lab.client().renames(from: "HEAD", to: nil)

        #expect(!lab.markerExists("submodule"))
    }
}

/// A repository built on disk with the real git, plus the payload scripts and markers of one vector.
private struct Lab {
    let directory: TemporaryDirectory
    let root: URL
    private let pool: BlockingOffloadPool

    init() throws {
        directory = TemporaryDirectory(prefix: "atelier-hostile")
        root = URL(filePath: directory.file("repo"), directoryHint: .isDirectory)
        pool = BlockingOffloadPool(width: 2)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
        try write("a.txt", "v1\n")
        try git("add", "a.txt")
        try git("commit", "-q", "-m", "base")
    }

    func cleanup() {
        pool.shutdown()
        directory.cleanup()
    }

    /// A client over this repository with a verdict cache of its own, so no test sees another's.
    func client(isolation: GitIsolation = .strict) -> GitClient {
        GitClient(
            repository: root, runner: HardenedProcessRunner(pool: pool), timeout: .seconds(30), isolation: isolation,
            gate: GitConfigGate())
    }

    /// Runs git outside the client under test, with an identity, no signing and the file protocol open, so the lab
    /// can build what a hostile repository looks like.
    @discardableResult
    func git(_ arguments: String..., input: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = GitClient.executable
        process.arguments =
            [
                "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "init.templateDir=",
                "-c", "protocol.file.allow=always"
            ] + arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if let input {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            try stdin.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// An executable script that leaves ``marker(_:)`` behind when it runs.
    func payload(_ name: String) throws -> String {
        let path = directory.file("payload-\(name).sh")
        try script(at: path, touching: marker(name))
        return path
    }

    func script(at path: String, touching marker: String) throws {
        try "#!/bin/sh\ntouch '\(marker)'\nexit 1\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    func marker(_ name: String) -> String { directory.file("marker-\(name)") }

    func markerExists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: marker(name)) }

    /// Makes a file's stat data differ from the index without changing its content, which is what an unpacked
    /// archive looks like and what makes git re-read the file through its filters.
    func age(_ path: String) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: path)
    }

    func ageWorkingTree() throws {
        try age(root.appending(path: "a.txt").path(percentEncoded: false))
    }

    /// Moves `HEAD` to a commit carrying a `gpgsig` header, which is what makes `log.showSignature` start the
    /// signature program. Written through `hash-object`, since git will not make one without a signing key.
    func commitSignedHead() throws {
        let tree = try git("rev-parse", "HEAD^{tree}")
        let object = """
            tree \(tree)
            author t <t@t> 1700000000 +0000
            committer t <t@t> 1700000000 +0000
            gpgsig -----BEGIN PGP SIGNATURE-----
            \u{20}
             iQEzBAABCAAdFiEE
             -----END PGP SIGNATURE-----

            signed

            """
        let hash = try git("hash-object", "-t", "commit", "-w", "--stdin", input: object)
        try git("update-ref", "HEAD", hash)
    }
}

extension GitError {
    /// The keys a ``GitError/refusedConfiguration(_:)`` names, or none for any other error.
    fileprivate var refusedKeys: [String] {
        guard case .refusedConfiguration(let keys) = self else { return [] }
        return keys
    }
}
