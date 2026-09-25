import DiffGit
import Foundation
import Testing

@testable import DiffComparison

/// `CommitGroupingEligibility`: when grouping by commit applies, and the reason and action when it does not.
struct CommitGroupingEligibilityTests {
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
    private static let main = ComparisonSource.gitRef(repository: repository, ref: "main")
    private static let feature = ComparisonSource.gitRef(repository: repository, ref: "feature")
    private static let workingTree = ComparisonSource.directory(URL(filePath: "/repo/", directoryHint: .isDirectory))

    private static func evaluate(
        placement: ExplorerPlacement = .unifiedSidebar, style: FileTreeStyle = .flat,
        left: ComparisonSource? = main, right: ComparisonSource? = feature, ancestry: CommitGroupingAncestry? = nil
    ) -> CommitGroupingEligibility {
        CommitGroupingEligibility.evaluate(
            placement: placement, style: style, left: left, right: right, ancestry: ancestry)
    }

    @Test
    func `two refs of one repository wait for the ancestry checks, then apply when the left is an ancestor`() {
        let range = CommitGroupingRange(
            repository: Self.repository, base: "main", tip: "feature", includesWorkingTree: false)

        #expect(Self.evaluate() == .needsAncestry(range))
        #expect(Self.evaluate(ancestry: .leftIsAncestor) == .applies(range))
        #expect(Self.evaluate(ancestry: .leftIsAncestor).ineligibility == nil)
    }

    @Test
    func `a ref against its repository's working tree lists up to HEAD and includes the working tree`() {
        #expect(
            Self.evaluate(right: Self.workingTree, ancestry: .leftIsAncestor)
                == .applies(
                    CommitGroupingRange(
                        repository: Self.repository, base: "main", tip: "HEAD", includesWorkingTree: true)))
    }

    @Test
    func `only the merged sidebar's flat list groups, checked before anything else`() {
        for placement in [ExplorerPlacement.top, .sidebar] {
            let verdict = Self.evaluate(placement: placement, style: .hierarchy, left: nil, right: nil)
            #expect(verdict == .doesNotApply(.needsMergedSidebar))
            #expect(verdict.ineligibility?.action == .useMergedSidebar)
        }
        for style in [FileTreeStyle.hierarchy, .compact] {
            let verdict = Self.evaluate(style: style, left: nil, right: nil)
            #expect(verdict == .doesNotApply(.needsFlatList))
            #expect(verdict.ineligibility?.action == .useFlatList)
        }
    }

    @Test
    func `folders, files, patches and a missing comparison have no history to group`() {
        let folder = ComparisonSource.directory(URL(filePath: "/elsewhere", directoryHint: .isDirectory))
        let file = ComparisonSource.file(URL(filePath: "/repo/a.swift"))
        let patch = URL(filePath: "/tmp/change.patch")
        let cases: [(ComparisonSource?, ComparisonSource?)] = [
            (folder, folder), (Self.main, folder), (file, file), (.patch(patch, side: .old), .patch(patch, side: .new)),
            (nil, nil), (Self.main, nil)
        ]

        for (left, right) in cases {
            let verdict = Self.evaluate(left: left, right: right, ancestry: .leftIsAncestor)
            #expect(verdict == .doesNotApply(.needsRepositoryStates))
            #expect(verdict.ineligibility?.action == nil)
        }
    }

    @Test
    func `refs of two repositories never group`() {
        let other = ComparisonSource.gitRef(repository: URL(filePath: "/other", directoryHint: .isDirectory), ref: "x")

        #expect(Self.evaluate(right: other, ancestry: .leftIsAncestor) == .doesNotApply(.differentRepositories))
    }

    @Test
    func `a newer state on the left offers Swap Sides`() {
        let reversed = Self.evaluate(ancestry: .rightIsAncestor)
        let workingTreeOnLeft = Self.evaluate(left: Self.workingTree, right: Self.main)

        #expect(reversed == .doesNotApply(.newerStateOnLeft))
        #expect(workingTreeOnLeft == .doesNotApply(.newerStateOnLeft))
        #expect(reversed.ineligibility?.action == .swapSides)
        #expect(reversed.ineligibility?.message == "The newer state is on the left.")
    }

    @Test
    func `diverged histories stay ungrouped and offer to compare from the merge base`() {
        let base = String(repeating: "3f2a9c1", count: 5) + "abcde"

        let verdict = Self.evaluate(ancestry: .diverged(mergeBase: base))
        let fromWorkingTree = Self.evaluate(right: Self.workingTree, ancestry: .diverged(mergeBase: base))

        #expect(verdict == .doesNotApply(.diverged(base: "main", tip: "feature", mergeBase: base)))
        #expect(verdict.ineligibility?.message == "main is not an ancestor of feature.")
        #expect(verdict.ineligibility?.action == .compareFromMergeBase(base))
        #expect(verdict.ineligibility?.action?.title == "Compare from Merge Base (3f2a9c1)")
        #expect(fromWorkingTree.ineligibility?.message == "main is not an ancestor of the working tree.")
    }

    @Test
    func `unrelated histories and unreadable ones say why, with no action`() {
        let unrelated = Self.evaluate(ancestry: .unrelated)
        let unreadable = Self.evaluate(ancestry: .unreadable("fatal: bad object"))

        #expect(unrelated == .doesNotApply(.unrelatedHistories))
        #expect(unreadable.ineligibility?.message == "Couldn't read the history: fatal: bad object")
        #expect(unrelated.ineligibility?.action == nil && unreadable.ineligibility?.action == nil)
    }
}
