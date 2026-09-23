import AemiCore
import AtelierFileTree
import DiffGit
import Foundation

/// Freshness wiring for ``DiffViewerModel``: outside changes reload, re-compare or refresh the comparison.
extension DiffViewerModel {
    /// Builds and wires this window's freshness watcher, gated by ``ViewerSettings/autoRefresh``. The watcher only
    /// attaches while the right side is the repository's own working tree.
    /// - Parameters:
    ///   - clock: Drives the watcher's debounces; tests inject a virtual one.
    ///   - makeWatcher: Builds the watcher's event source; a test substitutes a synthetic one.
    package func attachFreshness(
        clock: any Clock<Duration> = ContinuousClock(),
        makeWatcher: @escaping @Sendable () -> any WatchEventSource = { FileWatcher() }
    ) {
        let model = RepositoryFreshness(
            taskProvider: taskProvider, isEnabled: settings.autoRefresh, clock: clock, makeWatcher: makeWatcher)
        model.onTreeChanged = { [weak self] in self?.right.reload() }
        model.onHeadChanged = { [weak self] in self?.reloadForHeadChange() }
        model.onRefsChanged = { [weak self] in self?.refreshBothSidesRepositoryInfo() }
        model.onIndexChanged = { [weak self] in self?.refreshBadgeStates() }
        freshness = model
        left.onFetched = { [weak self] in self?.handleFetchCompleted(for: .left) }
        right.onFetched = { [weak self] in self?.handleFetchCompleted(for: .right) }
        updateFreshness()
    }

    /// Tells ``freshness`` the right side's root when it is the repository's own working tree, or nothing.
    func updateFreshness() {
        guard let freshness else { return }
        guard case .directory(let rightRoot) = right.source, let repository = right.repository else {
            freshness.comparisonChanged(rightSource: nil, repositoryRoot: nil)
            return
        }
        freshness.comparisonChanged(rightSource: .directory(rightRoot), repositoryRoot: repository.root)
    }

    /// `.git/HEAD` moved, so the diff's base may have too: compares again, re-resolving the left side's ref.
    private func reloadForHeadChange() {
        guard case .directory(let root) = right.source, case .gitRef(_, let leftRef) = left.source else { return }
        compareGitChanges(in: root, leftRef: leftRef)
    }

    /// A ref other than HEAD moved. A side parked on a named ref may now resolve to another commit, so both sides
    /// reload when either is; otherwise only their repository info, which feeds the menus, refreshes.
    private func refreshBothSidesRepositoryInfo() {
        guard !isParkedOnARef(left), !isParkedOnARef(right) else {
            reloadSources()
            return
        }
        taskProvider.task { [weak self] in
            await self?.left.refreshRepositoryInfo()
            await self?.right.refreshRepositoryInfo()
        }
    }

    /// Whether `side` is compared as a named ref (``SideState/RefChoice/ref(_:)``) rather than the working tree.
    private func isParkedOnARef(_ side: SideState) -> Bool {
        if case .ref = side.refChoice { true } else { false }
    }

    /// A fetch on `fetched`'s side landed: refreshes the other side's repository info when it shares the
    /// repository, and reloads both when either is parked on a remote-tracking ref the fetch could have moved.
    private func handleFetchCompleted(for fetched: Side) {
        let side = fetched == .left ? left : right
        let other = fetched == .left ? right : left
        guard let root = side.repository?.root else { return }
        taskProvider.task { [weak self] in
            guard let self, side.repository?.root == root else { return }
            let sharesRoot = other.repository?.root == root
            if sharesRoot { await other.refreshRepositoryInfo() }
            guard self.tracksRemoteRef(side) || (sharesRoot && self.tracksRemoteRef(other)) else { return }
            self.reloadSources()
        }
    }

    /// Whether `side` is parked on a ref under one of its repository's remotes, the refs a fetch moves.
    private func tracksRemoteRef(_ side: SideState) -> Bool {
        guard case .ref(let ref) = side.refChoice else { return false }
        return RepositoryFetch.isRemoteTrackingRef(ref, remotes: side.remoteNames)
    }
}
