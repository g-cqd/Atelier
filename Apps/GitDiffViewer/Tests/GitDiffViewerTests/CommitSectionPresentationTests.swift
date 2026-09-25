import AtelierFileTree
import DiffGit
import Foundation
import Testing

@testable import DiffComparison

/// How the grouped list presents its sections: default folds, remembered folds, notes and tooltips (GIT-06).
struct CommitSectionPresentationTests {
    private static func commit(_ id: String, subject: String = "Fix the ref menu's order") -> CommitGrouping.Commit {
        CommitGrouping.Commit(
            GitCommitChanges(
                id: id, parentIDs: ["p"], authorName: "Tess Ter", authorDate: Date(timeIntervalSince1970: 0),
                subject: subject, changes: []))
    }

    private static func section(
        _ kind: CommitGrouping.Kind, rows: [CommitGrouping.Row] = [], changedBack: Int = 0
    ) -> ExplorerSection {
        ExplorerSection(group: CommitGrouping.Section(kind: kind, rows: rows, changedBackCount: changedBack))
    }

    @Test
    func `up to twenty commits every section starts unfolded`() {
        let sections = [Self.section(.uncommitted)] + (1 ... 20).map { Self.section(.commit(Self.commit("c\($0)"))) }

        #expect(ExplorerSection.collapsedByDefault(sections).isEmpty)
    }

    @Test
    func `past twenty commits the commit and earlier sections start folded, uncommitted changes never`() {
        let commits = (1 ... 21).map { Self.section(.commit(Self.commit("c\($0)"))) }
        let sections = [Self.section(.uncommitted)] + commits + [Self.section(.earlier(unlistedCommitCount: 5))]

        let folded = ExplorerSection.collapsedByDefault(sections)

        #expect(folded == Set(commits.map(\.id) + ["earlier"]))
    }

    @Test
    @MainActor
    func `a fold the user made outranks the default, both ways, and outlives a rebuild`() {
        let state = ExplorerUIState()

        #expect(state.isCollapsed("commit:a", byDefault: true))
        state.setCollapsed(false, "commit:a")
        state.setCollapsed(true, "commit:b")

        #expect(!state.isCollapsed("commit:a", byDefault: true))
        #expect(state.isCollapsed("commit:b", byDefault: false))
        #expect(!state.isCollapsed("folder"))
    }

    @Test
    func `a section left empty by changes undone, and Earlier Changes, show inert lines`() {
        let emptied = Self.section(.commit(Self.commit("c1")), changedBack: 2)
        let earlier = Self.section(.earlier(unlistedCommitCount: 212), rows: [CommitGrouping.Row(path: "a.swift")])
        let plain = ExplorerSection(kind: .changes, title: "Files", nodes: [])

        #expect(emptied.noteLines == [CommitGrouping.Section.noNetChangesNote])
        #expect(earlier.noteLines == ["212 older commits not listed"])
        #expect(plain.noteLines.isEmpty)
    }

    @Test
    func `a commit header names the commit, its author and date, then what was changed back`() throws {
        let section = Self.section(
            .commit(Self.commit(String(repeating: "3f2a9c1", count: 5) + "abcde")), changedBack: 1)

        let tooltip = try #require(
            section.headerTooltip(includesMergedBranches: true, now: Date(timeIntervalSince1970: 86_400)))
        let lines = tooltip.components(separatedBy: "\n")

        #expect(lines.first?.hasPrefix("3f2a9c1 · Tess Ter · ") == true)
        #expect(
            Array(lines.dropFirst()) == [
                "Fix the ref menu's order", "1 file changed back", "History includes merged branches"
            ])
        #expect(section.title == "Fix the ref menu's order")
        #expect(
            ExplorerSection(kind: .ignored, title: "Ignored Files", nodes: [])
                .headerTooltip(
                    includesMergedBranches: false) == nil)
    }

    @Test
    func `a file's row names the path it had in its commit`() {
        let section = Self.section(
            .commit(Self.commit("c1")),
            rows: [
                CommitGrouping.Row(path: "a.swift", pathInChange: "old/a.swift"), CommitGrouping.Row(path: "b.swift")
            ])

        #expect(section.pathsInChange == ["a.swift": "old/a.swift"])
        #expect(section.nodes.map(\.id) == ["a.swift", "b.swift"])
    }
}
