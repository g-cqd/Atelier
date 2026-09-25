package import DiffGit
package import Foundation

/// The history a commit grouping lists: from the left side's ref to the right side's, in one repository.
package struct CommitGroupingRange: Sendable, Hashable {
    package let repository: URL
    /// The left side's ref, the older state.
    package let base: String
    /// The right side's ref, or `HEAD` when the right side is the working tree.
    package let tip: String
    /// Whether the right side is the working tree, whose uncommitted changes get a section of their own.
    package let includesWorkingTree: Bool

    package init(repository: URL, base: String, tip: String, includesWorkingTree: Bool) {
        self.repository = repository
        self.base = base
        self.tip = tip
        self.includesWorkingTree = includesWorkingTree
    }
}

/// How the range's two ends relate in history, as `GitClient.isAncestor` and `mergeBase` answer.
package enum CommitGroupingAncestry: Sendable, Hashable {
    /// The left side is an ancestor of the right, or the same commit.
    case leftIsAncestor
    /// The right side is an ancestor of the left: the comparison reads history backwards.
    case rightIsAncestor
    /// Both sides have commits of their own since `mergeBase`.
    case diverged(mergeBase: String)
    /// The two sides share no commit.
    case unrelated
    /// Git refused the repository's configuration, or failed; carries what it said.
    case unreadable(String)
}

/// The one-click way out of a state where grouping does not apply.
package enum CommitGroupingAction: Sendable, Hashable {
    case useMergedSidebar
    case useFlatList
    case swapSides
    /// Compare from this commit, the merge base, to the right side.
    case compareFromMergeBase(String)

    package var title: String {
        switch self {
            case .useMergedSidebar: "Use Merged Sidebar"
            case .useFlatList: "Use Flat List"
            case .swapSides: "Swap Sides"
            case .compareFromMergeBase(let commit): "Compare from Merge Base (\(GitCommit.abbreviated(commit)))"
        }
    }
}

/// Why grouping by commit does not apply to a window, in the order the conditions are checked (D30, D32).
package enum CommitGroupingIneligibility: Sendable, Hashable {
    case needsMergedSidebar
    case needsFlatList
    /// A side is a folder, a file or a patch, or there is no comparison: no history to list.
    case needsRepositoryStates
    case differentRepositories
    case unrelatedHistories
    /// The right side is an ancestor of the left, or the working tree is on the left.
    case newerStateOnLeft
    /// The left side is not an ancestor of the right; both have commits since `mergeBase`.
    case diverged(base: String, tip: String, mergeBase: String)
    /// Git could not answer; carries what it said.
    case historyUnreadable(String)

    /// The line the sidebar shows above the plain list, and the menu item's subtitle.
    package var message: String {
        switch self {
            case .needsMergedSidebar: "Grouping by commit needs the merged sidebar."
            case .needsFlatList: "Grouping by commit needs the flat list of paths."
            case .needsRepositoryStates: "Grouping by commit needs two states of one repository."
            case .differentRepositories: "The two sides are in different repositories."
            case .unrelatedHistories: "These states share no history."
            case .newerStateOnLeft: "The newer state is on the left."
            case .diverged(let base, let tip, _):
                "\(GitCommit.abbreviated(base)) is not an ancestor of \(GitCommit.abbreviated(tip))."
            case .historyUnreadable(let message): "Couldn't read the history: \(message)"
        }
    }

    /// The action offered beside the message, when there is one.
    package var action: CommitGroupingAction? {
        switch self {
            case .needsMergedSidebar: .useMergedSidebar
            case .needsFlatList: .useFlatList
            case .newerStateOnLeft: .swapSides
            case .diverged(_, _, let mergeBase): .compareFromMergeBase(mergeBase)
            case .needsRepositoryStates, .differentRepositories, .unrelatedHistories, .historyUnreadable: nil
        }
    }
}

/// Whether a window's file list can be grouped by commit: a pure verdict from its placement, its style, both
/// sides and, once git has answered, how they relate in history (GIT-06, D30, D32).
///
/// Grouping applies to the flat style of the merged sidebar only, when both sides are states of one repository (two
/// refs of it, or a ref on the left and its working tree on the right, as `SourceLoader.renames` draws the line) and
/// the left side is an ancestor of the right. The first condition that fails names the reason.
package enum CommitGroupingEligibility: Sendable, Hashable {
    case applies(CommitGroupingRange)
    /// Everything but the history holds: the ancestry checks over this range decide.
    case needsAncestry(CommitGroupingRange)
    case doesNotApply(CommitGroupingIneligibility)

    /// - Parameters:
    ///   - placement: Where the window's explorers sit; only the merged sidebar groups.
    ///   - style: How the explorers arrange files; only the flat list groups.
    ///   - left: The left side, the older state; nil before a comparison.
    ///   - right: The right side, the newer state; nil before a comparison.
    ///   - ancestry: What git answered for the range; nil before it has been asked.
    /// - Returns: The range when grouping applies, the range to check when only the history is left to judge, or
    ///   the first reason it does not apply.
    package static func evaluate(
        placement: ExplorerPlacement, style: FileTreeStyle, left: ComparisonSource?, right: ComparisonSource?,
        ancestry: CommitGroupingAncestry? = nil
    ) -> CommitGroupingEligibility {
        guard placement == .unifiedSidebar else { return .doesNotApply(.needsMergedSidebar) }
        guard style == .flat else { return .doesNotApply(.needsFlatList) }
        let range: CommitGroupingRange
        switch (left, right) {
            case (.gitRef(let repository, let base), .gitRef(let other, let tip)):
                guard sameFolder(repository, other) else { return .doesNotApply(.differentRepositories) }
                range = CommitGroupingRange(repository: repository, base: base, tip: tip, includesWorkingTree: false)
            case (.gitRef(let repository, let base), .directory(let folder)) where sameFolder(repository, folder):
                range = CommitGroupingRange(repository: repository, base: base, tip: "HEAD", includesWorkingTree: true)
            case (.directory(let folder), .gitRef(let repository, _)) where sameFolder(repository, folder):
                return .doesNotApply(.newerStateOnLeft)
            default:
                return .doesNotApply(.needsRepositoryStates)
        }
        switch ancestry {
            case nil: return .needsAncestry(range)
            case .leftIsAncestor: return .applies(range)
            case .rightIsAncestor: return .doesNotApply(.newerStateOnLeft)
            case .diverged(let mergeBase):
                let tip = range.includesWorkingTree ? "the working tree" : range.tip
                return .doesNotApply(.diverged(base: range.base, tip: tip, mergeBase: mergeBase))
            case .unrelated: return .doesNotApply(.unrelatedHistories)
            case .unreadable(let message): return .doesNotApply(.historyUnreadable(message))
        }
    }

    /// Why grouping does not apply, for the setting's subtitle and the sidebar's line; nil otherwise.
    package var ineligibility: CommitGroupingIneligibility? {
        if case .doesNotApply(let reason) = self { return reason }
        return nil
    }

    private static func sameFolder(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL == second.standardizedFileURL
    }
}
