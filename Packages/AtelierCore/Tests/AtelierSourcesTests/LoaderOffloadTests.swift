import AemiTestKit
import AtelierGit
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierSources

/// The loader's own blocking calls run on the pool it is given, never on a cooperative thread: the process shares
/// about one of those per core, so a read parked there starves unrelated tasks (Core S3, Aemi #25).
struct LoaderOffloadTests {
    /// A folder outside every repository, holding `files` by relative path.
    static func folder(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-offload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test
    func `a folder listing hashes every file inside a job of the injected pool`() async throws {
        let root = try Self.folder([
            "a.swift": "let a = 1\n", "b.swift": "let b = 2\n", "Sources/c.swift": "let c = 3\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let hashes = HashSpy(pool: pool)
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool, hashFile: hashes.hash)

        let entries = try await loader.entries(of: .directory(root))

        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.blobID != nil })
        #expect(hashes.calls.count == 3)
        #expect(hashes.calls.allSatisfy { $0.isInsideJob })
    }

    @Test
    func `a file's text is read in a job of the injected pool`() async throws {
        let root = try Self.folder(["a.swift": "let a = 1\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool)
        let entry = GitTreeEntry(relativePath: "a.swift", blobID: nil, size: 10)

        let text = try await loader.content(of: entry, in: .directory(root))

        #expect(text == "let a = 1\n")
        #expect(pool.jobs == 1)
    }

    /// An empty folder, so that no hashing job follows the scan and checks the cancellation in its stead.
    @Test(.timeLimit(.minutes(1)))
    func `a folder scan cancelled while it runs surfaces as a cancellation, not an empty listing`() async throws {
        let root = try Self.folder([:])
        defer { try? FileManager.default.removeItem(at: root) }
        let pool = OffloadSpy()
        defer { pool.shutdown() }
        let started = AsyncEventProbe<Void>()
        let gate = ThreadGate()
        // The scan is the listing's first job: hold it on its pool thread until the listing is cancelled.
        pool.atNextJobStart {
            started.record(())
            gate.waitUntilOpen()
        }
        let loader = SourceLoader(runner: FakeProcessRunner.outsideRepositories, offload: pool)
        let listing = Task { try await loader.entries(of: .directory(root)) }

        _ = try await started.wait(forAtLeast: 1, timeout: .seconds(15))
        listing.cancel()
        gate.open()

        await #expect(throws: CancellationError.self) { try await listing.value }
    }
}
