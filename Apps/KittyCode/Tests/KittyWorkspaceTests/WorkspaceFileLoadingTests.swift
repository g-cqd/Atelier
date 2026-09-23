import AemiIO
import AtelierText
import Darwin
import Foundation
import Synchronization
import Testing

@testable import KittyWorkspace

@Suite
struct WorkspaceFileLoadingTests {
    @Test(arguments: [
        ("a\nb\n", TextDocument.LineEnding.lineFeed), ("a\r\nb\r\n", .carriageReturnLineFeed),
        ("a\rb\r", .carriageReturn)
    ])
    func `a file loads with LF line breaks and remembers the ending it used`(
        bytes: String, lineEnding: TextDocument.LineEnding
    ) throws {
        let loaded = try WorkspaceFileLoading.decode(Data(bytes.utf8))

        #expect(Array(loaded.content.utf8) == Array("a\nb\n".utf8))
        #expect(loaded.lineEnding == lineEnding)
    }

    @Test func `bytes that are not UTF-8 are refused`() {
        #expect(throws: CocoaError.self) {
            try WorkspaceFileLoading.decode(Data([0x61, 0xFF, 0x62]))
        }
    }

    private func file(_ data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KittyLoad_\(UUID().uuidString).txt")
        try data.write(to: url)
        return url.path
    }

    @Test func `a file is read in the job the caller's offload runs`() async throws {
        let path = try file(Data("one\ntwo\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let jobs = Mutex(0)

        let loaded = try await WorkspaceFileLoading.readUTF8File(at: path) { read in
            jobs.withLock { $0 += 1 }
            return try read()
        }

        #expect(loaded.content == "one\ntwo\n")
        #expect(jobs.withLock { $0 } == 1)
    }

    @Test func `a file truncated between sizing and reading fails its read, not with a signal`() throws {
        let path = try file(Data(repeating: 0x61, count: 256 * 1024))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }

        #expect(throws: IOError.self) {
            try WorkspaceFileLoading.contents(
                of: TruncatedAfterSizing(file: file, path: path), maximumSize: WorkspaceFileLoading.maxFileSize)
        }
    }

    @Test func `a file over the size limit is refused before it is read`() async throws {
        let path = try file(Data("one\ntwo\n".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let error = await #expect(throws: CocoaError.self) {
            try await WorkspaceFileLoading.readUTF8File(at: path, maximumSize: 7) { read in try read() }
        }

        #expect(error?.code == .fileReadTooLarge)
    }

    @Test func `a missing file fails with the message Foundation's own reads give`() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("KittyLoad_\(UUID().uuidString)/gone.txt")
            .path

        let error = await #expect(throws: CocoaError.self) {
            try await WorkspaceFileLoading.readUTF8File(at: path) { read in try read() }
        }

        #expect(error?.code == .fileReadNoSuchFile)
        #expect(error?.localizedDescription == "The file “gone.txt” couldn’t be opened because there is no such file.")
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
