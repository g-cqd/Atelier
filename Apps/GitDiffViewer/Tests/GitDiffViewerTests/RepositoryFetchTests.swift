import Testing

@testable import DiffComparison

/// The pure pieces of the fetch feature: what the toolbar's fetch menu item should say.
struct RepositoryFetchTests {
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
