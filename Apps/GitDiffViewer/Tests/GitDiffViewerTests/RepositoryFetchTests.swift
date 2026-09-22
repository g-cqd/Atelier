import Testing

@testable import DiffComparison

/// The pure pieces of the fetch feature: what counts as a remote-tracking ref, and what the toolbar's fetch menu
/// item should say.
struct RepositoryFetchTests {
    @Test
    func `a ref shaped remote-slash-branch is remote-tracking when the remote is known`() {
        #expect(RepositoryFetch.isRemoteTrackingRef("origin/develop", remotes: ["origin"]))
    }

    @Test
    func `a local branch that happens to contain a slash is not remote-tracking`() {
        #expect(!RepositoryFetch.isRemoteTrackingRef("feature/foo", remotes: ["origin"]))
    }

    @Test
    func `a ref with no slash at all is not remote-tracking`() {
        #expect(!RepositoryFetch.isRemoteTrackingRef("main", remotes: ["origin"]))
    }

    @Test
    func `no known remotes means nothing is remote-tracking`() {
        #expect(!RepositoryFetch.isRemoteTrackingRef("origin/develop", remotes: []))
    }

    @Test
    func `menu item titles the primary remote when idle`() {
        let state = RepositoryFetch.MenuItem(remoteName: "upstream", isFetching: false, lastError: nil)
        #expect(state.title == "Fetch upstream…")
        #expect(state.isEnabled)
        #expect(state.errorLine == nil)
    }

    @Test
    func `menu item falls back to origin before a remote is known`() {
        let state = RepositoryFetch.MenuItem(remoteName: nil, isFetching: false, lastError: nil)
        #expect(state.title == "Fetch origin…")
    }

    @Test
    func `menu item is disabled and renamed while fetching`() {
        let state = RepositoryFetch.MenuItem(remoteName: "origin", isFetching: true, lastError: nil)
        #expect(state.title == "Fetching origin…")
        #expect(!state.isEnabled)
    }

    @Test
    func `menu item carries an error line naming the last failure`() {
        let state = RepositoryFetch.MenuItem(remoteName: "origin", isFetching: false, lastError: "no route to host")
        #expect(state.errorLine == "Fetch failed: no route to host")
        #expect(state.isEnabled)
    }
}
