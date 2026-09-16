import AemiRuntime
import AtelierProcess
import Foundation
import Testing

@testable import AtelierGit

struct GitClientTests {
    @Test
    func `many blobs are read through one batch process`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = GitClient.executable
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        try git("init", "-q")
        try "let a = 1\n".write(to: root.appending(path: "a.swift"), atomically: true, encoding: .utf8)
        try String(repeating: "line\n", count: 40_000)
            .write(to: root.appending(path: "big.swift"), atomically: true, encoding: .utf8)
        try git("add", ".")
        try git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let client = GitClient(repository: root, runner: HardenedProcessRunner(pool: pool))
        let entries = try await client.tree(at: "HEAD", isSupported: { _ in true })
        let ids = entries.compactMap(\.blobID)

        let blobs = try await client.blobs(ids + ["0000000000000000000000000000000000000000"])

        #expect(blobs.count == 2)
        #expect(blobs[ids[0]].map { String(decoding: $0, as: UTF8.self) } == "let a = 1\n")
        #expect(blobs[ids[1]]?.count == 5 * 40_000)
    }

    @Test
    func `batch output parsing keeps sizes exact and skips missing objects`() {
        let output = Data("aaa blob 3\nxyz\nbbb missing\nccc blob 0\n\n".utf8)

        let blobs = GitParsers.batch(output)

        #expect(blobs.keys.sorted() == ["aaa", "ccc"])
        #expect(blobs["aaa"] == Data("xyz".utf8))
        #expect(blobs["ccc"]?.isEmpty == true)
    }

    @Test
    func `tree records keep blobs with supported paths and drop trees and other files`() {
        let records = [
            "100644 blob 8e8ea3c1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7      12\tSources/a.swift",
            "040000 tree 1e8ea3c1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7       -\tSources",
            "100644 blob 2e8ea3c1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7 1048576\timage.png",
            "120000 blob 3e8ea3c1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7      20\tlink with space.swift"
        ]
        let output = Data((records.joined(separator: "\0") + "\0").utf8)

        let entries = GitParsers.tree(output) { $0.hasSuffix(".swift") }

        #expect(entries.map(\.relativePath) == ["Sources/a.swift", "link with space.swift"])
        #expect(entries.first?.blobID == "8e8ea3c1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7")
        #expect(entries.map(\.size) == [12, 20])
    }

    @Test
    func `rename records map old paths to new ones`() {
        let output = Data("R100\0old/a.swift\0new/a.swift\0R075\0b.swift\0c.swift\0".utf8)

        let renames = GitParsers.renames(output)

        #expect(renames == ["old/a.swift": "new/a.swift", "b.swift": "c.swift"])
    }

    @Test
    func `references keep their order and leave out remote HEAD pointers`() {
        let output = Data("feature/x\nmain\norigin/HEAD\norigin/main\nv1.0\n".utf8)

        #expect(GitParsers.references(output) == ["feature/x", "main", "origin/main", "v1.0"])
    }

    @Test
    func `commit lines split on the unit separator and skip malformed ones`() {
        let hash = String(repeating: "a", count: 40)
        let output = Data("\(hash)\u{1f}aaaaaaa\u{1f}Add a feature\u{1f}with a stray separator\nnot a commit\n".utf8)

        let commits = GitParsers.commits(output)

        #expect(commits.count == 1)
        #expect(
            commits.first
                == GitCommit(hash: hash, shortHash: "aaaaaaa", subject: "Add a feature\u{1f}with a stray separator"))
    }

    @Test
    func `full hashes are abbreviated and everything else is shown as typed`() {
        let sha1 = String(repeating: "0123456789", count: 4)
        let sha256 = String(repeating: "abcdef0123456789", count: 4)

        #expect(GitCommit.abbreviated(sha1) == "0123456")
        #expect(GitCommit.abbreviated(sha256) == "abcdef0")
        #expect(GitCommit.abbreviated("main") == "main")
        #expect(
            GitCommit.abbreviated("feature/a-branch-name-that-happens-to-be-forty")
                == "feature/a-branch-name-that-happens-to-be-forty")
        #expect(GitCommit.abbreviated(String(repeating: "g", count: 40)) == String(repeating: "g", count: 40))
    }

    @Test
    func `a failing command reports git's message`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let client = GitClient(repository: root, runner: HardenedProcessRunner(pool: pool))
        await #expect(throws: GitError.self) { try await client.resolve(ref: "HEAD") }
    }
}
