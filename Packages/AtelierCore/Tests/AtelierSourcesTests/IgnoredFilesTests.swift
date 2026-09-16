import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSources

struct IgnoredFilesTests {
    private func entry(_ path: String, _ blob: String) -> GitTreeEntry {
        GitTreeEntry(relativePath: path, blobID: blob, size: 1)
    }

    private func ignored(_ path: String) -> GitTreeEntry {
        GitTreeEntry(relativePath: path, blobID: nil, size: 0)
    }

    @Test
    func `ls-files records are NUL separated paths`() {
        #expect(GitParsers.paths(Data("a.swift\u{0}dir/b c.swift\u{0}\u{0}".utf8)) == ["a.swift", "dir/b c.swift"])
        #expect(GitParsers.paths(Data()).isEmpty)
    }

    @Test
    func `a repository folder lists what git sees, dotfiles included and ignored files apart`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-ignored-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "build"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = GitClient.executable
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        try git("init", "-q")
        try "build/\n".write(to: root.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "hidden\n".write(to: root.appending(path: ".hidden.txt"), atomically: true, encoding: .utf8)
        try "let a = 1\n".write(to: root.appending(path: "src/a.swift"), atomically: true, encoding: .utf8)
        try "gone\n".write(to: root.appending(path: "src/gone.swift"), atomically: true, encoding: .utf8)
        try git("add", ".")
        try git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init")
        try "let b = 2\n".write(to: root.appending(path: "src/untracked.swift"), atomically: true, encoding: .utf8)
        try "out\n".write(to: root.appending(path: "build/out.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appending(path: "src/gone.swift"))
        let loader = TestProcesses.loader

        let listed = try await loader.entries(of: .directory(root))
        let ignored = try await loader.ignoredEntries(of: .directory(root))

        #expect(
            listed.map(\.relativePath).sorted() == [".gitignore", ".hidden.txt", "src/a.swift", "src/untracked.swift"])
        #expect(listed.allSatisfy { $0.blobID != nil })
        #expect(ignored.map(\.relativePath) == ["build/out.txt"])
        #expect(ignored.allSatisfy { $0.blobID == nil })
    }

    @Test
    func `a plain folder is scanned without hidden files and has nothing ignored`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-plain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "hidden\n".write(to: root.appending(path: ".hidden.txt"), atomically: true, encoding: .utf8)
        try "a\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let loader = TestProcesses.loader

        #expect(try await loader.entries(of: .directory(root)).map(\.relativePath) == ["a.txt"])
        #expect(try await loader.ignoredEntries(of: .directory(root)).isEmpty)
    }
}
