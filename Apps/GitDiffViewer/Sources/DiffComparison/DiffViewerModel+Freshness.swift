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
        left.onFetched = { [weak self] in self?.handleFetchCompleted(for: .left) }
        right.onFetched = { [weak self] in self?.handleFetchCompleted(for: .right) }
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

    /// A loose or packed ref changed outside HEAD: a fetch moved a remote-tracking branch, a commit landed on the
    /// checked-out branch (which moves `refs/heads/<branch>` without touching the symbolic `.git/HEAD` file
    /// itself, so this fires instead of ``onHeadChanged``), a branch was created or deleted elsewhere.
    ///
    /// A side parked on a named ref (``SideState/refChoice`` is ``SideState/RefChoice/ref(_:)``, typically `HEAD`)
    /// resolves that name fresh on every ``SideState/reload()``, so it may now show a different commit than what
    /// is on screen; a side on the working tree does not name any ref and cannot be affected this way. Telling a
    /// ref that actually moved from a fixed SHA that merely looks like one would need a resolve this handler has
    /// no cheap way to reach from here, so this recomputes whenever either side names a ref at all rather than
    /// missing a real move -- a conservative trade of an occasional redundant reload for never showing a stale
    /// diff. Both sides on the working tree keeps the cheap menu-only refresh.
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

    /// A fetch on `fetched`'s side landed and its own repository info is already refreshed. Refreshes the other
    /// side too when it shares the same repository -- a fetch on one side updates the whole repository's remote
    /// refs, both sides' menus -- and re-runs the comparison, the same ``reloadSources()`` a manual reload would,
    /// when either side is parked on a remote-tracking ref the fetch could have moved: resolving a name like
    /// `origin/develop` again is exactly what shows the remote's new tip.
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

    /// Whether `side` is parked on a ref that names one of its repository's remotes, the ref shape a fetch's
    /// `refs/remotes/*` update actually moves.
    private func tracksRemoteRef(_ side: SideState) -> Bool {
        guard case .ref(let ref) = side.refChoice else { return false }
        return RepositoryFetch.isRemoteTrackingRef(ref, remotes: side.remoteNames)
    }
}
