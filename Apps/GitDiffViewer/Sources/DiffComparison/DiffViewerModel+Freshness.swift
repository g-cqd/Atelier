import AemiCore
import DiffGit
import Foundation

/// Freshness wiring for ``DiffViewerModel``, split out of the main file the way diagnostics and hover
/// documentation already are. `taskProvider`'s existing internal visibility is enough here — this file lives in
/// the same target as ``DiffViewerModel``.
extension DiffViewerModel {
    /// Builds and wires this window's freshness watcher, gated by ``ViewerSettings/autoRefresh``. Safe to call for
    /// every comparison window: a comparison whose right side is not the repository's own working tree (two refs,
    /// a patch, nothing loaded yet) simply never attaches a `FileWatcher` until one is.
    ///
    /// Left unwired to any window's launch: the caller that constructs comparison windows decides when to build
    /// one, the same way it decides when to call ``attachDiagnostics(engine:settings:)``.
    package func attachFreshness() {
        let model = RepositoryFreshness(taskProvider: taskProvider, isEnabled: settings.autoRefresh)
        model.onTreeChanged = { [weak self] in self?.right.reload() }
        model.onHeadChanged = { [weak self] in self?.reloadForHeadChange() }
        model.onRefsChanged = { [weak self] in self?.refreshBothSidesRepositoryInfo() }
        freshness = model
        updateFreshness()
    }

    /// Tells ``freshness`` what changed: the right side's on-disk root, when it is the repository's own working
    /// tree, or nothing otherwise. Called alongside ``updateDiagnostics()`` from ``sourcesChanged()``, so the
    /// watcher always tracks whatever is actually being compared.
    func updateFreshness() {
        guard let freshness else { return }
        guard case .directory(let rightRoot) = right.source, let repository = right.repository else {
            freshness.comparisonChanged(rightSource: nil, repositoryRoot: nil)
            return
        }
        freshness.comparisonChanged(rightSource: .directory(rightRoot), repositoryRoot: repository.root)
    }

    /// `.git/HEAD` changed: a checkout, a commit, a merge landing. Unlike a plain working-tree edit — which only
    /// needs ``SideState/reload()`` on the right side — the diff's *base* may have moved, so this re-runs the same
    /// prologue a fresh comparison would, re-resolving the left side's ref (typically `HEAD`, sometimes a named
    /// branch) against wherever it now points. The right side stays the working tree either way.
    private func reloadForHeadChange() {
        guard case .directory(let root) = right.source, case .gitRef(_, let leftRef) = left.source else { return }
        compareGitChanges(in: root, leftRef: leftRef)
    }

    /// A loose or packed ref changed outside HEAD: a fetch moved a remote-tracking branch, a branch was created or
    /// deleted elsewhere. Refreshes both sides' repository info (the branch/tag menus) without touching the diff
    /// itself — nothing the comparison is currently showing depends on a ref it isn't `HEAD` or checked out as.
    private func refreshBothSidesRepositoryInfo() {
        taskProvider.task { [weak self] in
            await self?.left.refreshRepositoryInfo()
            await self?.right.refreshRepositoryInfo()
        }
    }
}
