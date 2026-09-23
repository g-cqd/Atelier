import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSources

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

        let entries = try await TestProcesses.loader.entries(of: .directory(root))
            .sorted { $0.relativePath < $1.relativePath }

        #expect(entries.map(\.relativePath) == ["Sources/Nested/a.swift", "big.swift"])
        #expect(entries[0].blobID == SourceLoader.blobID(of: Data(source.utf8)))
        #expect(entries[0].size == source.utf8.count)
        #expect(entries[1].blobID == nil)
        #expect(entries[1].size == oversizeLength)
    }

    @Test
    func `a file that cannot be read is listed without a blob id instead of failing the folder`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-unreadable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "let a = 1\n".write(to: root.appending(path: "a.swift"), atomically: true, encoding: .utf8)
        let locked = root.appending(path: "locked.swift").path(percentEncoded: false)
        try "secret\n".write(toFile: locked, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)

        let entries = try await TestProcesses.loader.entries(of: .directory(root))
            .sorted { $0.relativePath < $1.relativePath }

        #expect(entries.map(\.relativePath) == ["a.swift", "locked.swift"])
        #expect(entries.first?.blobID == SourceLoader.blobID(of: Data("let a = 1\n".utf8)))
        #expect(entries.last?.blobID == nil)
    }
}
