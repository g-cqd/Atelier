import AemiIO
import AemiRuntime
import Darwin
import Foundation
import Testing

@testable import AtelierSearch

/// Each searched file is read once, with `pread` into memory the search owns, and searched only when it is text and
/// no larger than the cap (Aemi #3, Sec M3, Core S19).
struct WorkspaceSearchReadTests {
    private func withPool<T>(_ body: (BlockingOffloadPool) async throws -> T) async rethrows -> T {
        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }
        return try await body(pool)
    }

    private func file(_ data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "KittyWSRead_\(UUID().uuidString).txt")
        try data.write(to: url)
        return url.path(percentEncoded: false)
    }

    private func search(_ text: String, in path: String, maximumFileSize: Int = maximumSearchedFileSize) async
        -> SearchRunResult
    {
        await withPool { pool in
            await searchWorkspace(
                query: SearchQuery(text: text), files: [path], openBuffers: [:], pool: pool,
                maximumFileSize: maximumFileSize, onProgress: { _ in })
        }
    }

    @Test
    func `a file truncated between sizing and reading is skipped, not searched`() throws {
        let path = try file(Data(String(repeating: "needle\n", count: 40_000).utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }

        let lines = searchableLines(
            of: TruncatedAfterSizing(file: file, path: path), maximumSize: maximumSearchedFileSize)

        #expect(lines == nil)
    }

    @Test
    func `a file above the size cap is skipped`() async throws {
        let path = try file(Data("needle\nneedle\nneedle\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = await search("needle", in: path, maximumFileSize: 20)

        #expect(result.totalMatchCount == 0)
        #expect(result.filesSearched == 1)
    }

    @Test
    func `a file exactly at the size cap is searched`() async throws {
        let path = try file(Data("needle\nneedle\nneedle\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = await search("needle", in: path, maximumFileSize: 21)

        #expect(result.totalMatchCount == 3)
    }

    @Test
    func `a binary file is skipped by the search's own read`() async throws {
        let path = try file(Data("needle\n".utf8) + Data([0]) + Data("needle\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = await search("needle", in: path)

        #expect(result.totalMatchCount == 0)
        #expect(result.filesSearched == 1)
    }
}

/// A real file that another process truncates right after it is sized: the window in which reading through a mapping
/// raised SIGBUS.
private struct TruncatedAfterSizing: PositionalFile {
    let file: PosixFile
    let path: String

    func fileSize() throws -> Int {
        let size = try file.fileSize()
        try #require(truncate(path, 0) == 0)
        return size
    }

    func pread(into buffer: UnsafeMutableRawBufferPointer, at offset: Int) throws {
        try file.pread(into: buffer, at: offset)
    }
}
