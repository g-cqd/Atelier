import Foundation
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Testing

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
}
