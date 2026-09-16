import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

struct SourceLoaderTests {
    @Test
    func `a folder scan lists supported files by relative path and hashes only those small enough`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: "Sources/Nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "let a = 1\n"
        try source.write(to: root.appending(path: "Sources/Nested/a.swift"), atomically: true, encoding: .utf8)
        try source.write(to: root.appending(path: "node_modules/dependency.swift"), atomically: true, encoding: .utf8)
        try source.write(to: root.appending(path: ".hidden.swift"), atomically: true, encoding: .utf8)
        try source.write(to: root.appending(path: "notes.bin"), atomically: true, encoding: .utf8)
        let oversize = root.appending(path: "big.swift")
        let oversizeLength = SourceLoader.maximumHashedSize + 1
        try Data().write(to: oversize)
        let handle = try FileHandle(forWritingTo: oversize)
        try handle.truncate(atOffset: UInt64(oversizeLength))
        try handle.close()

        let entries = try await SourceLoader().entries(of: .directory(root))
            .sorted { $0.relativePath < $1.relativePath }

        #expect(entries.map(\.relativePath) == ["Sources/Nested/a.swift", "big.swift"])
        #expect(entries[0].blobID == SourceLoader.blobID(of: Data(source.utf8)))
        #expect(entries[0].size == source.utf8.count)
        #expect(entries[1].blobID == nil)
        #expect(entries[1].size == oversizeLength)
    }
}
