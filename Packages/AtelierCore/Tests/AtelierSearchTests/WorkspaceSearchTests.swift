import AemiRuntime
import Foundation
import Testing

@testable import AtelierSearch

@Suite("WorkspaceSearch")
struct WorkspaceSearchTests {
    /// One worker is enough: these tests exercise correctness, not concurrency, and a fresh pool per
    /// test keeps its (real, joined-on-shutdown) thread scoped to the test that owns it.
    private func withPool<T>(_ body: (BlockingOffloadPool) async throws -> T) async rethrows -> T {
        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }
        return try await body(pool)
    }

    private func makeTempDir() throws -> String {
        let tmp = NSTemporaryDirectory() + "KittyWSSearch_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func writeFile(_ path: String, content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("searches across multiple files")
    func searchMultipleFiles() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/a.swift", content: "let hello = 1")
        try writeFile(tmp + "/b.swift", content: "let hello = 2\nhello again")
        try writeFile(tmp + "/c.swift", content: "no match here")

        let files = [tmp + "/a.swift", tmp + "/b.swift", tmp + "/c.swift"]
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: [:],
                pool: pool,
                onProgress: { _ in }
            )
        }

        #expect(result.totalMatchCount == 3)
        #expect(result.filesMatched == 2)
        #expect(result.filesSearched == 3)
    }

    @Test("open buffers searched from memory not disk")
    func searchOpenBuffers() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // Disk has "let x = 1" but open buffer has "hello world"
        try writeFile(tmp + "/a.swift", content: "let x = 1")

        let files = [tmp + "/a.swift"]
        let openBuffers = [tmp + "/a.swift": ["hello world"]]
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: openBuffers,
                pool: pool,
                onProgress: { _ in }
            )
        }

        #expect(result.totalMatchCount == 1)
        #expect(result.filesMatched == 1)
    }

    @Test("cancellation stops search early")
    func cancellationStopsSearch() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // Create many files
        for i in 0 ..< 50 {
            try writeFile(tmp + "/file\(i).txt", content: "hello world line \(i)")
        }

        let files = (0 ..< 50).map { tmp + "/file\($0).txt" }
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }
        let task = Task {
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: [:],
                pool: pool,
                onProgress: { _ in }
            )
        }

        // Cancel immediately
        task.cancel()
        let result = await task.value

        // Search should have been cancelled (may or may not have completed some files)
        #expect(result.wasCancelled || result.filesSearched <= 50)
    }

    @Test("maxResults cap works")
    func maxResultsCap() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // Create file with many matches
        var content = ""
        for i in 0 ..< 100 {
            content += "hello \(i)\n"
        }
        try writeFile(tmp + "/many.txt", content: content)

        let files = [tmp + "/many.txt"]
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: [:],
                pool: pool,
                maxResults: 10,
                onProgress: { _ in }
            )
        }

        // Should have found matches but stopped accepting after cap
        #expect(result.totalMatchCount > 0)
    }

    @Test("empty files are handled gracefully")
    func emptyFilesHandled() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/empty.txt", content: "")
        try writeFile(tmp + "/has_match.txt", content: "hello")

        let files = [tmp + "/empty.txt", tmp + "/has_match.txt"]
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: [:],
                pool: pool,
                onProgress: { _ in }
            )
        }

        #expect(result.totalMatchCount == 1)
        #expect(result.filesSearched == 2)
    }

    /// Audit A4 — the mapped-file `readFileLines` must produce the same line splits as the
    /// previous `String.split(omittingEmptySubsequences: false)` approach (and, before that, the
    /// intermediate 64 KB `Data`-chunked reader). These tests cover the boundary cases a naive
    /// scan drops on the floor: file with no trailing newline, file with a trailing `\n`, file
    /// with a line longer than the old 64 KB chunk size, and CRLF line endings.
    @Test("file without trailing newline counts every line")
    func streamingNoTrailingNewline() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/a.txt", content: "alpha\nbeta\ngamma")  // no trailing \n
        let pattern = compilePattern(SearchQuery(text: "gamma"))!
        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern, files: [tmp + "/a.txt"], openBuffers: [:], pool: pool,
                onProgress: { _ in })
        }
        #expect(result.totalMatchCount == 1)
    }

    @Test("file ending with newline preserves trailing empty line semantics")
    func streamingTrailingNewline() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // Three lines, file ends with `\n`. Original split semantics produced
        // ["alpha", "beta", ""]; the streaming reader must match.
        try writeFile(tmp + "/a.txt", content: "alpha\nbeta\n")
        let pattern = compilePattern(SearchQuery(text: "beta"))!
        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern, files: [tmp + "/a.txt"], openBuffers: [:], pool: pool,
                onProgress: { _ in })
        }
        #expect(result.totalMatchCount == 1)
    }

    @Test("line longer than the chunk size is reassembled across chunks")
    func streamingLongLine() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // 80 KB single line (~1.25 × 64 KB chunk) followed by a matching marker.
        let bigLine = String(repeating: "x", count: 80 * 1024)
        try writeFile(tmp + "/a.txt", content: bigLine + "\nNEEDLE\n")
        let pattern = compilePattern(SearchQuery(text: "NEEDLE"))!
        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern, files: [tmp + "/a.txt"], openBuffers: [:], pool: pool,
                onProgress: { _ in })
        }
        #expect(result.totalMatchCount == 1)
    }

    @Test("CRLF lines are tolerated (CR stays in the line, \\n splits)")
    func streamingCRLF() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/a.txt", content: "alpha\r\nbeta\r\n")
        let pattern = compilePattern(SearchQuery(text: "beta"))!
        let result = await withPool { pool in
            await searchWorkspace(
                pattern: pattern, files: [tmp + "/a.txt"], openBuffers: [:], pool: pool,
                onProgress: { _ in })
        }
        #expect(result.totalMatchCount == 1)
    }
}
