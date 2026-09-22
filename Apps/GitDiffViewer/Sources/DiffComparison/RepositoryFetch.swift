import Foundation

/// Pure pieces of the fetch feature, kept out of ``SideState`` and the toolbar so both can be tested the same way
/// the rest of the model is: no AppKit, no runner, no repository, just the small decisions the UI and the
/// freshness wiring make from what a side already knows about its own fetch.
package enum RepositoryFetch {
    /// Whether `ref` names a remote-tracking branch of one of `remotes`: it has a `remote/branch` shape, and the
    /// part before the first slash is actually one of the repository's remotes, not just any branch that happens
    /// to contain a slash (`feature/foo` in a repository with no remote named `feature`).
    package static func isRemoteTrackingRef(_ ref: String, remotes: [String]) -> Bool {
        guard let slash = ref.firstIndex(of: "/") else { return false }
        return remotes.contains(String(ref[ref.startIndex ..< slash]))
    }

    /// What the toolbar's fetch menu item should say and whether it can be clicked, from what the side currently
    /// knows: the remote's name once read (``SideState/remoteNames``), whether a fetch is already running, and the
    /// last one's failure, if any.
    package struct MenuItem: Equatable {
        package let title: String
        package let isEnabled: Bool
        /// A second, disabled line naming the last failure, shown right under the fetch item until the next
        /// successful fetch clears it; nil when the last fetch (or none yet) did not fail.
        package let errorLine: String?

        package init(remoteName: String?, isFetching: Bool, lastError: String?) {
            let name = remoteName ?? "origin"
            title = isFetching ? "Fetching \(name)…" : "Fetch \(name)…"
            isEnabled = !isFetching
            errorLine = lastError.map { "Fetch failed: \($0)" }
        }
    }
}
