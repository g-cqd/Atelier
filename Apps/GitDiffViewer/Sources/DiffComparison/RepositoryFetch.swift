import Foundation

/// The pure decisions of the fetch feature, made from what a side already knows about its own fetch.
package enum RepositoryFetch {
    /// The toolbar's fetch menu item: its title, whether it can be clicked, and the last failure.
    package struct MenuItem: Equatable {
        package let title: String
        package let isEnabled: Bool
        /// A disabled line under the fetch item naming the last failure; nil when the last fetch did not fail.
        package let errorLine: String?

        package init(remoteName: String?, isFetching: Bool, lastError: String?) {
            let name = remoteName ?? "origin"
            title = isFetching ? "Fetching \(name)…" : "Fetch \(name)…"
            isEnabled = !isFetching
            errorLine = lastError.map { "Fetch failed: \($0)" }
        }
    }
}
