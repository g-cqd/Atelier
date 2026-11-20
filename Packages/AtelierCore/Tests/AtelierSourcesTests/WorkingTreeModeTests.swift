import AtelierGit
import Foundation
import Testing

@testable import AtelierSources

/// Modes and submodules: a ref and a working tree list each file with the mode git records, and a submodule with
/// the commit it records, shown as `git diff` shows it.
struct WorkingTreeModeTests {
    private func modes(_ entries: [GitTreeEntry]) -> [String: String?] {
        Dictionary(entries.map { ($0.relativePath, $0.mode) }, uniquingKeysWith: { first, _ in first })
    }

    @Test
    func `a ref and its clean working tree list the same modes`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.write("run.sh", "echo hi\n")
        try repository.link("link.txt", to: "a.txt")
        try repository.git("add", "-A")
        try repository.git("update-index", "--chmod=+x", "run.sh")
        try repository.git("commit", "-q", "-m", "initial")
        try repository.git("checkout", "--", "run.sh")

        let head = try await TestProcesses.loader.entries(of: .gitRef(repository: repository.root, ref: "HEAD"))
        let workingTree = try await TestProcesses.loader.entries(of: .directory(repository.root))

        #expect(modes(head) == ["a.txt": "100644", "run.sh": "100755", "link.txt": "120000"])
        #expect(modes(workingTree) == modes(head))
    }

    @Test
    func `making a file executable changes its working-tree mode, not its blob`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("run.sh", "echo hi\n")
        try repository.commit("initial")
        let path = repository.root.appending(path: "run.sh").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

        let ids = try await repository.headAndWorkingTree()
        let workingTree = try await TestProcesses.loader.entries(of: .directory(repository.root))

        #expect(ids.workingTree["run.sh"] == ids.head["run.sh"])
        #expect(modes(workingTree)["run.sh"] == "100755")
    }

    @Test
    func `a plain folder lists no modes`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "modes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "a\n".write(to: folder.appending(path: "a.txt"), atomically: true, encoding: .utf8)

        let entries = try await TestProcesses.loader.entries(of: .directory(folder))

        #expect(entries.map(\.mode) == [nil])
    }

    @Test
    func `a submodule is listed with its recorded commit, and reads as git diff shows it`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.commit("initial")
        let first = try repository.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.git("update-index", "--add", "--cacheinfo", "160000,\(first),sub")
        try repository.git("commit", "-q", "-m", "add submodule")
        try repository.write("a.txt", "b\n")
        try repository.git("add", "a.txt")
        try repository.git("commit", "-q", "-m", "second")
        let second = try repository.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.git("update-index", "--cacheinfo", "160000,\(second),sub")
        try repository.git("commit", "-q", "-m", "bump submodule")
        let loader = TestProcesses.loader
        let old = ComparisonSource.gitRef(repository: repository.root, ref: "HEAD~1")
        let new = ComparisonSource.gitRef(repository: repository.root, ref: "HEAD")

        let oldEntry = try #require(try await loader.entries(of: old).first { $0.relativePath == "sub" })
        let newEntry = try #require(try await loader.entries(of: new).first { $0.relativePath == "sub" })
        let texts = try await loader.contents(of: [newEntry], in: new)

        #expect(oldEntry.isSubmodule && oldEntry.blobID == first)
        #expect(newEntry.blobID == second)
        #expect(try await loader.content(of: oldEntry, in: old) == "Subproject commit \(first)\n")
        #expect(texts == ["sub": "Subproject commit \(second)\n"])
    }

    @Test
    func `a working tree lists a submodule with the commit its index records`() async throws {
        let repository = try SourceRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")
        try repository.commit("initial")
        let first = try repository.git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.git("update-index", "--add", "--cacheinfo", "160000,\(first),sub")
        try repository.git("commit", "-q", "-m", "add submodule")
        // A submodule that is not checked out: its folder is there, empty.
        try FileManager.default.createDirectory(
            at: repository.root.appending(path: "sub"),
            withIntermediateDirectories: true
        )

        let entries = try await TestProcesses.loader.entries(of: .directory(repository.root))
        let sub = try #require(entries.first { $0.relativePath == "sub" })

        #expect(sub.isSubmodule && sub.blobID == first)
    }
}
