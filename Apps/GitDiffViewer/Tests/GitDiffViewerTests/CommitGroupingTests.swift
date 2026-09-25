import AtelierFileTree
import DiffGit
import Foundation
import Testing

@testable import DiffComparison

/// `CommitGrouping`: which commit section each changed file of a comparison lands in (GIT-06).
struct CommitGroupingTests {
    private static func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    private static func comparison(
        left: [SourceEntry], right: [SourceEntry], renames: [String: String] = [:]
    ) -> Comparison {
        Comparison(left: left, right: right, leftSource: nil, rightSource: nil, gitRenames: renames)
    }

    private static func commit(_ id: String, parent: String? = nil, _ changes: GitFileChange...) -> GitCommitChanges {
        GitCommitChanges(
            id: id, parentIDs: parent.map { [$0] } ?? ["parent-of-\(id)"], authorName: "Tess",
            authorDate: Date(timeIntervalSince1970: 0), subject: "Commit \(id)", changes: changes)
    }

    private static func modified(_ path: String) -> GitFileChange { GitFileChange(status: .modified, path: path) }
    private static func added(_ path: String) -> GitFileChange { GitFileChange(status: .added, path: path) }
    private static func deleted(_ path: String) -> GitFileChange { GitFileChange(status: .deleted, path: path) }
    private static func renamed(_ old: String, _ new: String) -> GitFileChange {
        GitFileChange(status: .renamed, path: new, oldPath: old)
    }

    /// Each section's id and its rows' paths, in order.
    private static func layout(_ grouping: CommitGrouping) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: grouping.sections.map { ($0.id, $0.rows.map(\.path)) })
    }

    @Test
    func `a file two commits changed sits under both, and each section lists its own files`() {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1"), Self.entry("b.swift", "2")],
            right: [Self.entry("a.swift", "3"), Self.entry("b.swift", "4")])
        let commits = [
            Self.commit("new", parent: "old", Self.modified("a.swift"), Self.modified("b.swift")),
            Self.commit("old", parent: "base", Self.modified("a.swift"))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true, baseCommit: "base")

        #expect(grouping.sections.map(\.id) == ["commit:new", "commit:old"])
        #expect(Self.layout(grouping) == ["commit:new": ["a.swift", "b.swift"], "commit:old": ["a.swift"]])
        #expect(!grouping.leavesFirstParentChain)
    }

    @Test
    func `a file changed then changed back has no row, and a section left empty says so`() {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1"), Self.entry("b.swift", "2")],
            right: [Self.entry("a.swift", "1"), Self.entry("b.swift", "5")])
        let commits = [
            Self.commit("revert", Self.modified("a.swift"), Self.modified("b.swift")),
            Self.commit("change", Self.modified("a.swift"))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(Self.layout(grouping) == ["commit:revert": ["b.swift"], "commit:change": []])
        #expect(grouping.sections.map(\.changedBackCount) == [1, 1])
        #expect(grouping.sections[0].note == nil)
        #expect(grouping.sections[1].note == CommitGrouping.Section.noNetChangesNote)
    }

    @Test
    func `a file added then deleted within the range has no row either`() {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])
        let commits = [
            Self.commit("delete", Self.deleted("tmp.swift")),
            Self.commit("add", Self.added("tmp.swift"), Self.modified("a.swift"))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(Self.layout(grouping) == ["commit:delete": [], "commit:add": ["a.swift"]])
        #expect(grouping.sections.map(\.changedBackCount) == [1, 1])
    }

    @Test
    func `renames are followed through each commit to the comparison's own row, which keeps the new name`() throws {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1")], right: [Self.entry("dir/c.swift", "3")],
            renames: ["a.swift": "dir/c.swift"])
        let commits = [
            Self.commit("edit", Self.modified("dir/c.swift")),
            Self.commit("second", Self.renamed("b.swift", "dir/c.swift")),
            Self.commit("touch", Self.modified("b.swift")),
            Self.commit("first", Self.renamed("a.swift", "b.swift"))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        let rows = grouping.sections.map(\.rows)
        #expect(rows.map { $0.map(\.path) } == [["a.swift"], ["a.swift"], ["a.swift"], ["a.swift"]])
        #expect(rows.map { $0.first?.pathInChange } == [nil, nil, "b.swift", "b.swift"])
        #expect(comparison.displayPath(for: try #require(rows.first?.first).path) == "dir/c.swift")
    }

    @Test
    func `a rename the net diff split into a deletion and an addition lands on both rows`() {
        let comparison = Self.comparison(left: [Self.entry("old.swift", "1")], right: [Self.entry("new.swift", "2")])
        let commits = [Self.commit("move", Self.renamed("old.swift", "new.swift"))]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(Self.layout(grouping) == ["commit:move": ["new.swift", "old.swift"]])
    }

    @Test
    func `two files swapping names in one commit each keep their own identity`() {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1"), Self.entry("b.swift", "2")],
            right: [Self.entry("a.swift", "2"), Self.entry("b.swift", "1"), Self.entry("c.swift", "3")])
        let commits = [
            Self.commit("later", Self.added("c.swift")),
            Self.commit("swap", Self.renamed("a.swift", "b.swift"), Self.renamed("b.swift", "a.swift"))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(Self.layout(grouping) == ["commit:later": ["c.swift"], "commit:swap": ["a.swift", "b.swift"]])
    }

    @Test
    func `uncommitted changes come first when the right side is the working tree`() {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1")],
            right: [Self.entry("a.swift", "2"), Self.entry("untracked.swift", "3")])
        let commits = [Self.commit("one", Self.modified("a.swift"))]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits,
            uncommitted: [Self.modified("a.swift"), Self.added("untracked.swift")], isComplete: true)

        #expect(grouping.sections.map(\.id) == ["uncommitted", "commit:one"])
        #expect(grouping.sections.first?.rows.map(\.path) == ["a.swift", "untracked.swift"])
    }

    @Test
    func `no uncommitted section without working tree changes`() {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])
        let commits = [Self.commit("one", Self.modified("a.swift"))]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: [], isComplete: true)

        #expect(grouping.sections.map(\.id) == ["commit:one"])
    }

    @Test
    func `net files no listed commit touched go into Earlier Changes when the listing stopped short`() {
        let comparison = Self.comparison(
            left: [Self.entry("a.swift", "1"), Self.entry("b.swift", "2"), Self.entry("same.swift", "9")],
            right: [Self.entry("a.swift", "3"), Self.entry("b.swift", "4"), Self.entry("same.swift", "9")])
        let commits = [Self.commit("newest", Self.modified("a.swift"))]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: false, unlistedCommitCount: 1_200)

        #expect(grouping.sections.map(\.id) == ["commit:newest", "earlier"])
        #expect(grouping.sections.last?.kind == .earlier(unlistedCommitCount: 1_200))
        #expect(grouping.sections.last?.rows.map(\.path) == ["b.swift"])
    }

    @Test
    func `a complete listing that explains every file has no Earlier Changes`() {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: [Self.commit("one", Self.modified("a.swift"))], uncommitted: nil,
            isComplete: true)

        #expect(!grouping.sections.contains { $0.id == "earlier" })
    }

    @Test
    func `rows follow the flat list's order`() {
        let paths = ["b/file10.swift", "a.swift", "b/file2.swift", "B.swift"]
        let comparison = Self.comparison(
            left: paths.map { Self.entry($0, "1") }, right: paths.map { Self.entry($0, "2") })
        let commits = [
            GitCommitChanges(
                id: "one", parentIDs: [], authorName: "", authorDate: Date(timeIntervalSince1970: 0), subject: "",
                changes: paths.map(Self.modified))
        ]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(grouping.sections.first?.rows.map(\.path) == PathNode.flatList(from: paths).map(\.id))
        #expect(grouping.sections.first?.rows.map(\.path).suffix(2) == ["b/file2.swift", "b/file10.swift"])
    }

    @Test
    func `an empty commit keeps its section and says it changed no file`() {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])
        let commits = [Self.commit("empty"), Self.commit("one", Self.modified("a.swift"))]

        let grouping = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(grouping.sections.first?.note == CommitGrouping.Section.noFileChangesNote)
    }

    @Test
    func `a complete listing whose oldest commit does not start from the left side leaves the first-parent chain`() {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])
        let commits = [Self.commit("merge", parent: "mainline", Self.modified("a.swift"))]

        let off = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true, baseCommit: "inside-branch")
        let on = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true, baseCommit: "mainline")
        let partial = CommitGrouping.build(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: false, baseCommit: "inside-branch")

        #expect(off.leavesFirstParentChain)
        #expect(!on.leavesFirstParentChain)
        #expect(!partial.leavesFirstParentChain)
    }

    @Test
    @MainActor
    func `the off-main build answers what the synchronous one does`() async {
        let comparison = Self.comparison(left: [Self.entry("a.swift", "1")], right: [Self.entry("a.swift", "2")])
        let commits = [Self.commit("one", Self.modified("a.swift"))]

        let offMain = await CommitGrouping.buildOffMain(
            comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)

        #expect(
            offMain
                == CommitGrouping.build(comparison: comparison, commits: commits, uncommitted: nil, isComplete: true))
    }
}
