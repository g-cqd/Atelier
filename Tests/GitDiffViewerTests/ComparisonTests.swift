import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

struct ComparisonTests {
    private func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    @Test
    func `statuses and exact renames come from blob ids`() {
        let comparison = Comparison(
            left: [entry("a.swift", "1"), entry("b.swift", "2"), entry("old/name.swift", "3")],
            right: [
                entry("a.swift", "1"), entry("b.swift", "9"), entry("new/name.swift", "3"), entry("added.swift", "4")
            ],
            leftSource: nil, rightSource: nil
        )

        #expect(
            comparison.statuses == [
                "a.swift": .same, "b.swift": .different, "old/name.swift": .renamed, "added.swift": .onlyRight
            ])
        #expect(comparison.counterpartPath(of: "old/name.swift", in: .left) == "new/name.swift")
        #expect(comparison.counterpartPath(of: "new/name.swift", in: .right) == "old/name.swift")
        #expect(comparison.changedPaths(under: nil, limit: 10) == ["added.swift", "b.swift", "old/name.swift"])
        #expect(comparison.changedPaths(under: "old", limit: 10) == ["old/name.swift"])
        #expect(comparison.changedPathCount == 3)
    }

    @Test
    func `git renames refine the comparison without overriding exact ones`() {
        var comparison = Comparison(
            left: [entry("a.swift", "1"), entry("x.swift", "5")], right: [entry("b.swift", "2"), entry("y.swift", "5")],
            leftSource: nil, rightSource: nil)
        #expect(comparison.statuses["a.swift"] == .onlyLeft)

        comparison.merge(gitRenames: ["a.swift": "b.swift", "x.swift": "elsewhere.swift"])

        #expect(comparison.statuses["a.swift"] == .renamed)
        #expect(comparison.counterpartPath(of: "x.swift", in: .left) == "y.swift")
        #expect(comparison.isRenamedWithChanges("a.swift"))
        #expect(!comparison.isRenamedWithChanges("x.swift"))
    }

    @Test
    func `explorer trees carry directory statuses and honour the filter and style`() {
        let comparison = Comparison(
            left: [entry("z/same.swift", "1"), entry("a/x/changed.swift", "2")],
            right: [entry("z/same.swift", "1"), entry("a/x/changed.swift", "8")],
            leftSource: nil, rightSource: nil
        )
        let leftTree = FileNode.tree(from: ["z/same.swift", "a/x/changed.swift"])

        let full = ExplorerTrees.build(
            comparison: comparison, leftTree: leftTree, rightTree: leftTree, showsChangesOnly: false, style: .hierarchy)
        #expect(full.statuses["a"] == .different)
        #expect(full.statuses["z"] == .same)
        #expect(full.left.map(\.id) == ["a", "z"])

        let filtered = ExplorerTrees.build(
            comparison: comparison, leftTree: leftTree, rightTree: leftTree, showsChangesOnly: true, style: .flat)
        #expect(filtered.left.map(\.id) == ["a/x/changed.swift"])
    }

    @Test
    func `change navigation wraps and reports a one-based position`() {
        var navigator = ChangeNavigator()
        #expect(navigator.current(count: 3) == nil)
        navigator.next(count: 3)
        #expect(navigator.current(count: 3) == 1)
        navigator.previous(count: 3)
        #expect(navigator.current(count: 3) == 3)
        navigator.next(count: 0)
        #expect(navigator.current(count: 0) == nil)
        navigator.reset()
        #expect(navigator.current(count: 3) == nil)
    }
}
