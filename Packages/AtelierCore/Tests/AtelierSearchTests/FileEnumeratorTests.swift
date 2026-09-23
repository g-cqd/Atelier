import Foundation
import Testing

@testable import AtelierSearch

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

    /// The enumerator opens no file: the search's one read of each file finds the binary ones.
    @Test
    func `a binary file is listed, left to the search's own read`() throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }

        try writeFile(tmp + "/text.txt", content: "hello world")
        try Data([0x48, 0x65, 0x6C, 0x00, 0x6C, 0x6F]).write(to: URL(fileURLWithPath: tmp + "/binary.bin"))

        let files = enumerateSearchableFiles(rootPath: tmp)

        #expect(Set(files.map { URL(fileURLWithPath: $0).lastPathComponent }) == ["text.txt", "binary.bin"])
    }

    @Test(arguments: ["", "/"])
    func `an ignored directory is not walked`(suffix: String) throws {
        let tmp = try makeTempDir()
        defer { cleanup(tmp) }
        try writeFile(tmp + "/keep.swift", content: "hello")
        try FileManager.default.createDirectory(
            atPath: tmp + "/Generated/Deep", withIntermediateDirectories: true)
        try writeFile(tmp + "/Generated/a.swift", content: "hello")
        try writeFile(tmp + "/Generated/Deep/b.swift", content: "hello")

        let files = enumerateSearchableFiles(rootPath: tmp, gitIgnoredPaths: [tmp + "/Generated" + suffix])

        #expect(files == [tmp + "/keep.swift"])
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
