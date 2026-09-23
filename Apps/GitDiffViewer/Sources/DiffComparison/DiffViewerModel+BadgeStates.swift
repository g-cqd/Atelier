/// Badge states for ``DiffViewerModel``: where each path stands against the index, and keeping that current.
extension DiffViewerModel {
    /// Where the change at `leftPath`, a file or a folder, stands against the index: the state the unified explorer's
    /// row, the path's tab and its card header draw their badge in.
    package func badgeState(ofPath leftPath: String) -> BadgeChangeState {
        unifiedBadgeStates.state(of: leftPath)
    }

    /// Re-reads git's status on each side that is a folder, for its badges alone: the files, the comparison and the
    /// diffs stay as they are.
    package func refreshBadgeStates() {
        left.refreshBadgeStates()
        right.refreshBadgeStates()
    }

    /// Rebuilds ``unifiedBadgeStates`` and each side's ``SideState/explorerBadgeStates`` from both sides' states and
    /// the comparison's renames. The unified and left explorers name a path by its left-side path, the right explorer
    /// by its own, and all three draw a change in the same state (CARD-11). The right explorer merges the unified
    /// states back rather than the left side's own, so a pair git names twice, as it names a rename it has not
    /// recorded (a deleted old path and an untracked new one), draws its one state on both sides.
    func updateUnifiedBadgeStates() {
        let comparison = comparison
        let rightStates = right.badgeStates
        let unified = BadgeChangeStates.merged(left.badgeStates, with: rightStates) {
            comparison.counterpartPath(of: $0, in: .right)
        }
        unifiedBadgeStates = unified
        left.showComparisonBadgeStates(unified)
        right.showComparisonBadgeStates(
            .merged(rightStates, with: unified) { comparison.counterpartPath(of: $0, in: .left) })
    }
}
