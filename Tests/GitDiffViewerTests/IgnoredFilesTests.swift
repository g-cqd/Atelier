import DiffCore
import Foundation
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Testing

struct IgnoredFilesTests {
    private func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    private func ignored(_ path: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: nil, size: 0)
    }

    @Test
    func `ls-files records are NUL separated paths`() {
        #expect(GitClient.parsePaths(Data("a.swift\u{0}dir/b c.swift\u{0}\u{0}".utf8)) == ["a.swift", "dir/b c.swift"])
        #expect(GitClient.parsePaths(Data()).isEmpty)
    }

    @Test
    func `ignored files are listed and diffable but never changes`() {
        var comparison = Comparison(
            left: [entry("a.swift", "1")], right: [entry("a.swift", "2")], leftSource: nil, rightSource: nil,
            rightIgnored: [ignored("build/out.txt"), ignored("build/deep/gen.txt")]
        )

        #expect(comparison.statuses.keys.sorted() == ["a.swift"])
        #expect(comparison.changedPathCount == 1)
        #expect(comparison.changedPaths(under: nil, limit: 10) == ["a.swift"])
        #expect(comparison.changedPaths(under: "build", limit: 10) == ["build/deep/gen.txt", "build/out.txt"])
        #expect(comparison.isFile("build/out.txt"))
        #expect(comparison.contains("build"))
        #expect(comparison.isIgnored("build/out.txt"))
        #expect(!comparison.isIgnored("a.swift"))
        #expect(comparison.pair(for: "build/out.txt").old == nil)
        #expect(comparison.pair(for: "build/out.txt").new?.relativePath == "build/out.txt")
        #expect(comparison.summaryKind(for: "build/out.txt", directoryStatus: nil) == .added)

        comparison.setIgnored(left: [ignored("left/only.txt")], right: [ignored("build/other.txt")])

        #expect(comparison.ignoredPaths == ["left/only.txt", "build/other.txt"])
        #expect(comparison.rightEntries["build/out.txt"] == nil)
        #expect(comparison.summaryKind(for: "left/only.txt", directoryStatus: nil) == .deleted)
        #expect(comparison.statuses.keys.sorted() == ["a.swift"])
    }

    @Test
    func `the explorer trees put ignored files in their own trees only when shown`() {
        let comparison = Comparison(
            left: [entry("a.swift", "1")], right: [entry("a.swift", "2")], leftSource: nil, rightSource: nil,
            rightIgnored: [ignored("build/out.txt")]
        )
        let leftTree = FileNode.tree(from: ["a.swift"])
        let rightTree = FileNode.tree(from: ["a.swift"])

        let hidden = ExplorerTrees.build(comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: true, style: .hierarchy)
        #expect(hidden.unified.flatMap(\.filePaths) == ["a.swift"])
        #expect(hidden.unifiedIgnored.isEmpty)

        let shown = ExplorerTrees.build(comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: true, showsIgnoredFiles: true, style: .compact)
        #expect(shown.unified.flatMap(\.filePaths) == ["a.swift"])
        #expect(shown.rightIgnored.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(shown.leftIgnored.isEmpty)
        #expect(shown.unifiedIgnored.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(shown.statuses["build/out.txt"] == nil)
    }

    @Test
    func `a repository folder lists what git sees, dotfiles included and ignored files apart`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gdv-ignored-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        let loader = SourceLoader()

        let listed = try await loader.entries(of: .directory(root))
        let ignored = try await loader.ignoredEntries(of: .directory(root))

        #expect(listed.map(\.relativePath).sorted() == [".gitignore", ".hidden.txt", "src/a.swift", "src/untracked.swift"])
        #expect(listed.allSatisfy { $0.blobID != nil })
        #expect(ignored.map(\.relativePath) == ["build/out.txt"])
        #expect(ignored.allSatisfy { $0.blobID == nil })
    }

    @Test
    func `a plain folder is scanned without hidden files and has nothing ignored`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gdv-plain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "hidden\n".write(to: root.appending(path: ".hidden.txt"), atomically: true, encoding: .utf8)
        try "a\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        let loader = SourceLoader()

        #expect(try await loader.entries(of: .directory(root)).map(\.relativePath) == ["a.txt"])
        #expect(try await loader.ignoredEntries(of: .directory(root)).isEmpty)
    }
}
