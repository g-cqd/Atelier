import AtelierGit
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// Ignored files in the comparison and the explorer trees: listed and diffable, never counted as changes.
struct IgnoredSectionTests {
    private func entry(_ path: String, _ blob: String) -> GitTreeEntry {
        GitTreeEntry(relativePath: path, blobID: blob, size: 1)
    }

    private func ignored(_ path: String) -> GitTreeEntry {
        GitTreeEntry(relativePath: path, blobID: nil, size: 0)
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

        let hidden = ExplorerTrees.build(
            comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: true, style: .hierarchy)
        #expect(hidden.unified.flatMap(\.filePaths) == ["a.swift"])
        #expect(hidden.unifiedIgnored.isEmpty)

        let shown = ExplorerTrees.build(
            comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: true,
            showsIgnoredFiles: true, style: .compact)
        #expect(shown.unified.flatMap(\.filePaths) == ["a.swift"])
        #expect(shown.rightIgnored.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(shown.leftIgnored.isEmpty)
        #expect(shown.unifiedIgnored.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(shown.statuses["build/out.txt"] == nil)
    }
}
