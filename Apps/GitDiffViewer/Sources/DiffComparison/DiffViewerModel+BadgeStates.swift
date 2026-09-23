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

    /// Rebuilds ``unifiedBadgeStates`` from both sides' states and the comparison's renames.
    func updateUnifiedBadgeStates() {
        let comparison = comparison
        unifiedBadgeStates = .merged(left: left.badgeStates, right: right.badgeStates) {
            comparison.counterpartPath(of: $0, in: .right)
        }
    }
}
