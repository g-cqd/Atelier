import Foundation
import Testing

@testable import KittySearch

@Suite("FileEnumerator")
struct FileEnumeratorTests {
    private func makeTempDir() throws -> String {
        let rawTmp = NSTemporaryDirectory() + "KittySearchTest_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: rawTmp, withIntermediateDirectories: true)
        // Resolve symlinks so paths match what FileManager.enumerator returns
        return URL(fileURLWithPath: rawTmp).resolvingSymlinksInPath().path
    }

    private func writeFile(_ path: String, content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("enumerates files in temp directory")
    func enumeratesFiles() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/a.swift", content: "let x = 1")
        try writeFile(tmp + "/b.txt", content: "hello")
        try FileManager.default.createDirectory(
            atPath: tmp + "/sub", withIntermediateDirectories: true)
        try writeFile(tmp + "/sub/c.swift", content: "let y = 2")

        let files = enumerateSearchableFiles(rootPath: tmp)
        #expect(files.count == 3)
        #expect(files.contains(where: { $0.hasSuffix("a.swift") }))
        #expect(files.contains(where: { $0.hasSuffix("b.txt") }))
        #expect(files.contains(where: { $0.hasSuffix("c.swift") }))
    }

    @Test("excludes hidden files when includeHidden is false")
    func excludesHiddenFiles() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/visible.txt", content: "hello")
        try writeFile(tmp + "/.hidden.txt", content: "secret")

        let files = enumerateSearchableFiles(rootPath: tmp, includeHidden: false)
        #expect(files.count == 1)
        #expect(files[0].hasSuffix("visible.txt"))
    }

    @Test("includes hidden files when includeHidden is true")
    func includesHiddenFiles() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/visible.txt", content: "hello")
        try writeFile(tmp + "/.hidden.txt", content: "secret")

        let files = enumerateSearchableFiles(rootPath: tmp, includeHidden: true)
        #expect(files.count == 2)
    }

    @Test("excludes gitignored paths")
    func excludesGitIgnored() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/keep.txt", content: "hello")
        try writeFile(tmp + "/ignore.txt", content: "world")

        let ignoredPaths: Set<String> = [tmp + "/ignore.txt"]
        let files = enumerateSearchableFiles(rootPath: tmp, gitIgnoredPaths: ignoredPaths)
        #expect(files.count == 1)
        #expect(files[0].hasSuffix("keep.txt"))
    }

    @Test("excludes binary files")
    func excludesBinaryFiles() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/text.txt", content: "hello world")
        // Write binary file with null bytes
        let binaryData = Data([0x48, 0x65, 0x6C, 0x00, 0x6C, 0x6F])
        try binaryData.write(to: URL(fileURLWithPath: tmp + "/binary.bin"))

        let files = enumerateSearchableFiles(rootPath: tmp)
        #expect(files.count == 1)
        #expect(files[0].hasSuffix("text.txt"))
    }

    @Test("excludes .git directory")
    func excludesGitDirectory() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/keep.txt", content: "hello")
        try FileManager.default.createDirectory(
            atPath: tmp + "/.git", withIntermediateDirectories: true)
        try writeFile(tmp + "/.git/config", content: "git config")

        let files = enumerateSearchableFiles(rootPath: tmp, includeHidden: true)
        #expect(files.count == 1)
        #expect(files[0].hasSuffix("keep.txt"))
    }

    @Test("empty directory returns empty list")
    func emptyDirectory() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        let files = enumerateSearchableFiles(rootPath: tmp)
        #expect(files.isEmpty)
    }
}
