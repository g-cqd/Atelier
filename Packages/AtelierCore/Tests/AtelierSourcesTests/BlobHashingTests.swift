import AemiIO
import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel
import Darwin
import Foundation
import Testing

@testable import AtelierSources

struct BlobHashingTests {
    @Test(arguments: ["", "hello\n", String(repeating: "x", count: 100_000)])
    func `a file's blob id matches the Data based one and git's blob format`(content: String) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString).txt")
        let data = Data(content.utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try SourceLoader.blobID(atPath: url.path(percentEncoded: false))

        #expect(read == SourceLoader.blobID(of: data))
        if content == "hello\n" {
            #expect(read == "ce013625030ba8dba906f756967f9e9ca394464a")
        }
    }

    @Test
    func `a file hashed after it shrank is hashed as it now is`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString).txt")
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path(percentEncoded: false)

        #expect(try SourceLoader.blobID(atPath: path) == "ce013625030ba8dba906f756967f9e9ca394464a")
        try Data().write(to: url)
        #expect(try SourceLoader.blobID(atPath: path) == SourceLoader.blobID(of: Data()))
    }

    @Test
    func `a file truncated between sizing and reading fails its hash with a short read, not a signal`() throws {
        let path = try Self.largeFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }

        #expect(throws: IOError.self) { try SourceLoader.blobID(of: TruncatedAfterSizing(file: file, path: path)) }
    }

    @Test
    func `a file truncated between sizing and reading fails its read with a short read, not a signal`() throws {
        let path = try Self.largeFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }

        #expect(throws: IOError.self) { try SourceLoader.contents(of: TruncatedAfterSizing(file: file, path: path)) }
    }

    @Test
    func `a read of a missing file fails with the message Foundation's own reads give`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString)/missing.swift")

        let error = await #expect(throws: CocoaError.self) { try await FileSource.read(url, on: TestProcesses.pool) }

        #expect(error?.code == .fileReadNoSuchFile)
        #expect(
            error?.localizedDescription == "The file “missing.swift” couldn’t be opened because there is no such file.")
    }

    /// A file of many pages, so a read past a truncation would touch pages the file no longer has.
    private static func largeFile() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString).txt")
        try Data(repeating: 0x61, count: 256 * 1024).write(to: url)
        return url.path(percentEncoded: false)
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
