import AtelierGit
import Foundation
import Testing

@testable import AtelierSources

/// A working tree listed against HEAD: a file git reports clean has HEAD's blob, whatever its form on disk, and a
/// changed file has the blob of its bytes.
struct WorkingTreeIndexTests {
    @Test
    func `a committed symbolic link is unchanged, and listed with the blob of its target path`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("target.txt", "hello\n")
        try repository.link("link.txt", to: "target.txt")
        try repository.commit("initial")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["link.txt"] == ids.head["link.txt"])
        #expect(ids.workingTree["link.txt"] == .some(SourceLoader.blobID(of: Data("target.txt".utf8))))
    }

    @Test
    func `a retargeted symbolic link changes, and reads as its new target path`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.write("b.txt", "b\n")
        try repository.link("link.txt", to: "a.txt")
        try repository.commit("initial")
        try repository.link("link.txt", to: "b.txt")

        let ids = try await repository.headAndWorkingTree()
        let entry = GitTreeEntry(relativePath: "link.txt", blobID: ids.workingTree["link.txt"] ?? nil, size: 5)
        let text = try await TestProcesses.loader.content(of: entry, in: .directory(repository.root))

        #expect(ids.workingTree["link.txt"] == .some(SourceLoader.blobID(of: Data("b.txt".utf8))))
        #expect(text == "b.txt")
    }

    @Test(arguments: ["Pods/Lib/Lib.swift", "node_modules/pkg/index.js", "app/DerivedData/x.swift", "Carthage/C.swift"])
    func `a tracked file under a folder a plain scan skips is listed`(path: String) async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write(path, "let a = 1\n")
        try repository.commit("initial")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree[path] == ids.head[path])
    }

    @Test
    func `a clean file over the hashing limit is unchanged`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("big.txt", String(repeating: "0123456789abcdef\n", count: 600_000))
        try repository.commit("initial")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["big.txt"] == ids.head["big.txt"])
    }

    @Test
    func `a file git checks out with CRLF is unchanged, and reads as git stores it`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write(".gitattributes", "*.txt text eol=crlf\n")
        try repository.write("a.txt", "one\ntwo\n")
        try repository.commit("initial")
        try repository.delete("a.txt")
        try repository.git("checkout", "--", "a.txt")
        #expect(try Data(contentsOf: repository.root.appending(path: "a.txt")) == Data("one\r\ntwo\r\n".utf8))

        let ids = try await repository.headAndWorkingTree()
        let entry = GitTreeEntry(relativePath: "a.txt", blobID: ids.workingTree["a.txt"] ?? nil, size: 10)
        let text = try await TestProcesses.loader.content(of: entry, in: .directory(repository.root))

        #expect(ids.workingTree["a.txt"] == ids.head["a.txt"])
        #expect(text == "one\ntwo\n")
    }

    @Test
    func `a file outside a sparse checkout's cone is unchanged`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("keep/a.txt", "a\n")
        try repository.write("skip/b.txt", "b\n")
        try repository.commit("initial")
        try repository.git("sparse-checkout", "set", "keep")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["skip/b.txt"] == ids.head["skip/b.txt"])
    }

    @Test
    func `a file marked skip-worktree is unchanged, as git shows it, whatever its local edit`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.commit("initial")
        try repository.git("update-index", "--skip-worktree", "a.txt")
        try repository.write("a.txt", "local\n")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["a.txt"] == ids.head["a.txt"])
    }

    @Test
    func `an edited, a staged and an untracked file have the blobs of their bytes`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("edited.txt", "a\n")
        try repository.write("staged.txt", "s\n")
        try repository.commit("initial")
        try repository.write("edited.txt", "b\n")
        try repository.write("staged.txt", "t\n")
        try repository.git("add", "staged.txt")
        try repository.write("new.txt", "n\n")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["edited.txt"] == .some(SourceLoader.blobID(of: Data("b\n".utf8))))
        #expect(ids.workingTree["staged.txt"] == .some(SourceLoader.blobID(of: Data("t\n".utf8))))
        #expect(ids.workingTree["new.txt"] == .some(SourceLoader.blobID(of: Data("n\n".utf8))))
    }

    @Test
    func `a deleted file is not listed`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.commit("initial")
        try repository.delete("a.txt")

        let ids = try await repository.headAndWorkingTree()

        #expect(ids.workingTree["a.txt"] == nil)
    }

    @Test
    func `a subfolder of a repository lists its own clean and changed files, relative to itself`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("sub/a.txt", "a\n")
        try repository.write("sub/b.txt", "b\n")
        try repository.write("other.txt", "o\n")
        try repository.commit("initial")
        try repository.write("sub/b.txt", "c\n")

        let entries = try await TestProcesses.loader.entries(of: .directory(repository.root.appending(path: "sub")))
        let ids = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.blobID) })

        #expect(Set(ids.keys) == ["a.txt", "b.txt"])
        #expect(ids["a.txt"] == .some(SourceLoader.blobID(of: Data("a\n".utf8))))
        #expect(ids["b.txt"] == .some(SourceLoader.blobID(of: Data("c\n".utf8))))
    }
}
