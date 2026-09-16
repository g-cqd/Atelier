import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSources

struct BlobHashingTests {
    @Test(arguments: ["", "hello\n", String(repeating: "x", count: 100_000)])
    func `memory mapped blob id matches the Data based one and git's blob format`(content: String) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString).txt")
        let data = Data(content.utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let mapped = try SourceLoader.blobID(atPath: url.path(percentEncoded: false), size: data.count)

        #expect(mapped == SourceLoader.blobID(of: data))
        if content == "hello\n" {
            #expect(mapped == "ce013625030ba8dba906f756967f9e9ca394464a")
        }
    }

    @Test
    func `a file that shrank after the scan is hashed at its size on disk, not the stale one`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "gdv-\(UUID().uuidString).txt")
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path(percentEncoded: false)

        // The scan saw a longer file; mapping that length would touch pages past the end and take SIGBUS.
        #expect(try SourceLoader.blobID(atPath: path, size: 100_000) == "ce013625030ba8dba906f756967f9e9ca394464a")
        try Data().write(to: url)
        #expect(try SourceLoader.blobID(atPath: path, size: 6) == SourceLoader.blobID(of: Data()))
    }
}
