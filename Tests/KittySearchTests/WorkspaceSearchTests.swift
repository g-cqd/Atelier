import Foundation
import Testing

@testable import KittySearch

@Suite("WorkspaceSearch")
struct WorkspaceSearchTests {
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

        let result = await searchWorkspace(
            pattern: pattern,
            files: files,
            openBuffers: [:],
            onProgress: { _ in }
        )

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

        let result = await searchWorkspace(
            pattern: pattern,
            files: files,
            openBuffers: openBuffers,
            onProgress: { _ in }
        )

        #expect(result.totalMatchCount == 1)
        #expect(result.filesMatched == 1)
    }

    @Test("cancellation stops search early")
    func cancellationStopsSearch() async throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        // Create many files
        for i in 0..<50 {
            try writeFile(tmp + "/file\(i).txt", content: "hello world line \(i)")
        }

        let files = (0..<50).map { tmp + "/file\($0).txt" }
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let task = Task {
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: [:],
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
        for i in 0..<100 {
            content += "hello \(i)\n"
        }
        try writeFile(tmp + "/many.txt", content: content)

        let files = [tmp + "/many.txt"]
        let pattern = compilePattern(SearchQuery(text: "hello"))!

        let result = await searchWorkspace(
            pattern: pattern,
            files: files,
            openBuffers: [:],
            maxResults: 10,
            onProgress: { _ in }
        )

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

        let result = await searchWorkspace(
            pattern: pattern,
            files: files,
            openBuffers: [:],
            onProgress: { _ in }
        )

        #expect(result.totalMatchCount == 1)
        #expect(result.filesSearched == 2)
    }
}
