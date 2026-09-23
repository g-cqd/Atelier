import AemiCore
import AtelierFileTree
import DiffGit
import Foundation

/// Freshness wiring for ``DiffViewerModel``: outside changes reload a side, refresh the menus or refresh the badges.
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
        model.treeChangeFilter = { [weak self] paths in
            await self?.right.listingMayChange(at: paths) ?? false
        }
        model.onTreeChanged = { [weak self] in self?.right.reload() }
        model.onHeadChanged = { [weak self] in self?.refsMoved() }
        model.onRefsChanged = { [weak self] in self?.refsMoved() }
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

    /// `HEAD` or another ref moved: a commit, a checkout, a fetch, a new branch or tag. Both menus read the refs
    /// again (GIT-01), and each side parked on a ref reloads only when the commit it names moved (GDV S3), so a fetch
    /// that moves nothing on screen reloads nothing, and a commit reloads the `HEAD` side alone.
    private func refsMoved() {
        taskProvider.task { [weak self] in
            guard let self else { return }
            let refreshed = await left.refreshRepositoryInfo()
            if let refreshed, right.repository?.root == refreshed.root {
                right.updateRepositoryInfo(refreshed)
            } else {
                await right.refreshRepositoryInfo()
            }
        }
        left.reloadIfRefMoved()
        right.reloadIfRefMoved()
    }

    /// A fetch on `fetched`'s side landed and refreshed that side's repository info: the other side takes the same
    /// info when it shares the repository, and each side parked on a ref the fetch moved reloads. The watcher's own
    /// notice of the same refs then reloads nothing more, since its check waits for that reload and finds the commit
    /// current.
    private func handleFetchCompleted(for fetched: Side) {
        let side = fetched == .left ? left : right
        let other = fetched == .left ? right : left
        if let info = side.repository { other.updateRepositoryInfo(info) }
        left.reloadIfRefMoved()
        right.reloadIfRefMoved()
    }
}
