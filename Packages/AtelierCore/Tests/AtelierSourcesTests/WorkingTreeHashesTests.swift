import AtelierGit
import AtelierProcess
import AtelierTestSupport
import Darwin
import Foundation
import Testing

@testable import AtelierSources

/// A reload hashes only the files whose stamp changed since the folder's last listing (PERF-08): the rest keep the
/// blob ids the loader holds for them.
struct WorkingTreeHashesTests {
    /// When the test files were last modified: long enough before any read for their hashes to be kept.
    private static let past = Date(timeIntervalSince1970: 1_577_836_800)
    /// A later modification time, for a file changed since.
    private static let later = Date(timeIntervalSince1970: 1_609_459_200)

    /// A folder outside every repository, whose files were all last modified at ``past``.
    private static func folder(_ files: [String: String]) throws -> URL {
        let root = try LoaderOffloadTests.folder(files)
        for path in files.keys { try touch(root.appending(path: path), at: past) }
        return root
    }

    private static func touch(_ url: URL, at date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    private static func blobID(_ text: String) -> String {
        SourceLoader.blobID(of: Data(text.utf8))
    }

    private static func ids(_ entries: [GitTreeEntry]) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.blobID) })
    }

    @Test
    func `a reload with one changed file hashes that file alone`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n", "b.swift": "let b = 2\n", "c.swift": "let c = 3\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool, hashFile: hashes.hash)
        _ = try await loader.entries(of: .directory(root))
        let changed = root.appending(path: "b.swift")
        try "let b = 22\n".write(to: changed, atomically: false, encoding: .utf8)
        try Self.touch(changed, at: Self.later)

        let reloaded = try await loader.entries(of: .directory(root))

        #expect(Array(hashes.names.dropFirst(3)) == ["b.swift"])
        #expect(
            Self.ids(reloaded)
                == [
                    "a.swift": Self.blobID("let a = 1\n"), "b.swift": Self.blobID("let b = 22\n"),
                    "c.swift": Self.blobID("let c = 3\n")
                ])
    }

    @Test
    func `in a repository, a reload with one changed file hashes that file alone`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n", "Sources/b.swift": "let b = 2\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let toplevel = root.standardizedFileURL.path(percentEncoded: false)
        let runner = FakeProcessRunner { spec in
            if spec.arguments.contains("--show-toplevel") { return .success(toplevel + "\n") }
            if spec.arguments.contains("ls-files") { return .success("a.swift\0Sources/b.swift\0") }
            // The configuration listing: an empty one refuses nothing.
            return .success("")
        }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: runner, offload: pool, hashFile: hashes.hash)
        _ = try await loader.entries(of: .directory(root))
        let changed = root.appending(path: "Sources/b.swift")
        try "let b = 22\n".write(to: changed, atomically: false, encoding: .utf8)
        try Self.touch(changed, at: Self.later)

        let reloaded = try await loader.entries(of: .directory(root))

        #expect(Array(hashes.names.dropFirst(2)) == ["b.swift"])
        #expect(Self.ids(reloaded)["Sources/b.swift"] == Self.blobID("let b = 22\n"))
    }

    @Test
    func `a file rewritten in place to the same size is hashed again, told apart by its modification time`()
        async throws
    {
        let root = try Self.folder(["a.swift": "let a = 1\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool, hashFile: hashes.hash)
        _ = try await loader.entries(of: .directory(root))
        let file = root.appending(path: "a.swift")
        let before = try #require(FileStamp(regularFileAt: file.path(percentEncoded: false)))
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("let z = 9\n".utf8))
        try handle.close()
        try Self.touch(file, at: Self.later)
        let after = try #require(FileStamp(regularFileAt: file.path(percentEncoded: false)))
        try #require(after.inode == before.inode && after.size == before.size && after.device == before.device)

        let reloaded = try await loader.entries(of: .directory(root))

        #expect(hashes.names == ["a.swift", "a.swift"])
        #expect(reloaded.first?.blobID == Self.blobID("let z = 9\n"))
    }

    @Test
    func `a file replaced by one of the same size and time is hashed again, told apart by its inode`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool, hashFile: hashes.hash)
        _ = try await loader.entries(of: .directory(root))
        let file = root.appending(path: "a.swift")
        let replacement = root.appending(path: "a.swift.new")
        try "let z = 9\n".write(to: replacement, atomically: false, encoding: .utf8)
        try Self.touch(replacement, at: Self.past)
        try #require(rename(replacement.path(percentEncoded: false), file.path(percentEncoded: false)) == 0)

        let reloaded = try await loader.entries(of: .directory(root))

        #expect(hashes.names == ["a.swift", "a.swift"])
        #expect(reloaded.first?.blobID == Self.blobID("let z = 9\n"))
    }

    /// A modification time ahead of the read, as a network volume's clock can give: nothing yet rules out a second
    /// write within the same clock tick.
    @Test
    func `a file not yet modified two seconds before its read is hashed again on the next reload`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.touch(root.appending(path: "a.swift"), at: Date(timeIntervalSince1970: 4_102_444_800))
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool, hashFile: hashes.hash)

        _ = try await loader.entries(of: .directory(root))
        _ = try await loader.entries(of: .directory(root))

        #expect(hashes.names == ["a.swift", "a.swift"])
    }

    @Test
    func `a deleted file's kept id goes with the next listing`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n", "b.swift": "let b = 2\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool)
        _ = try await loader.entries(of: .directory(root))
        try FileManager.default.removeItem(at: root.appending(path: "b.swift"))

        _ = try await loader.entries(of: .directory(root))

        let kept = loader.workingTreeHashes.entries(of: root.standardizedFileURL.path(percentEncoded: false))
        #expect(Array(kept.keys) == ["a.swift"])
    }
}
