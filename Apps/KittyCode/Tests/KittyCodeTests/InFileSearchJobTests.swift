import AemiTesting
import KittySearch
import Testing

@testable import KittyEditor

/// Each editor state owns its in-file search: a newer search, a cancellation and `shutdown()` stop only that state's,
/// and a stopped search never applies its result.
@Suite
@MainActor
struct InFileSearchJobTests {
    private func makeState(tasks: TaskProviderSpy) -> EditorState {
        EditorTestHarness.make(fileContent: ["id0", "none", "id2"], taskProvider: tasks).state
    }

    /// Starts a search for `query` in `state`, as typing in the find field does.
    private func startSearch(_ query: String, in state: EditorState) {
        var search = EditorState.InFileSearch(
            query: query, pattern: nil, matches: [], activeMatchIndex: -1, isCaseSensitive: false, isRegex: false,
            isWholeWord: false)
        scheduleInFileSearch(&search, state: state, pipeline: nil)
        state.inFileSearch = search
    }

    @Test
    func `a search that finishes applies its matches and lets go of its task`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let state = makeState(tasks: tasks)
        defer { state.shutdown() }

        startSearch("id", in: state)
        try await tasks.waitForAllTasks()

        #expect(state.inFileSearch?.matches.map(\.row) == [0, 2])
        #expect(state.inFileSearchTask == nil)
    }

    @Test
    func `a newer search cancels the one before it, whose result never applies`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let state = makeState(tasks: tasks)
        defer { state.shutdown() }

        startSearch("none", in: state)
        let first = try #require(state.inFileSearchTask)
        startSearch("id", in: state)
        try await tasks.waitForAllTasks()

        #expect(first.isCancelled)
        #expect(state.inFileSearch?.query == "id")
        #expect(state.inFileSearch?.matches.map(\.row) == [0, 2])
    }

    @Test
    func `cancelling one state's search leaves another state's running`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let cancelled = makeState(tasks: tasks)
        let other = makeState(tasks: tasks)
        defer {
            cancelled.shutdown()
            other.shutdown()
        }

        startSearch("id", in: cancelled)
        startSearch("id", in: other)
        let cancelledTask = try #require(cancelled.inFileSearchTask)
        let otherTask = try #require(other.inFileSearchTask)
        cancelInFileSearch(state: cancelled)
        try await tasks.waitForAllTasks()

        #expect(cancelledTask.isCancelled)
        #expect(!otherTask.isCancelled)
        #expect(cancelled.inFileSearch?.matches.isEmpty == true)
        #expect(other.inFileSearch?.matches.map(\.row) == [0, 2])
    }

    @Test
    func `shutting the state down cancels its search, whose result never applies`() async throws {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        let state = makeState(tasks: tasks)

        startSearch("id", in: state)
        let running = try #require(state.inFileSearchTask)
        state.shutdown()
        try await tasks.waitForAllTasks()

        #expect(running.isCancelled)
        #expect(state.inFileSearchTask == nil)
        #expect(state.inFileSearch?.matches.isEmpty == true)
    }
}
