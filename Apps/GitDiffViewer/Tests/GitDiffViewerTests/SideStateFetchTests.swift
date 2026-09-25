import AemiTesting
import AtelierTestSupport
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``SideState/fetch()``: its runner, the arguments and isolation it sends git, its success and failure paths,
/// and the remote names ``SideState/loadRemotesIfNeeded()`` reads for it.
@MainActor
@Suite(.mainActorLane)
struct SideStateFetchTests {
    private nonisolated static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private nonisolated static let info = RepositoryInfo(
        root: root, branches: ["main", "origin/develop"], tags: [], commits: [])

    private func makeSUT(runner: any ProcessRunner, taskProvider: TaskProviderSpy = .tolerant()) -> SideState {
        SideState(
            label: "Right", reader: SourceLoader(runner: runner, pool: LoaderTestPool.shared),
            taskProvider: taskProvider)
    }

    private nonisolated static func remotesOutput(_ names: [String] = ["origin"]) -> ProcessOutput {
        .success(names.map { "\($0)\tgit@example.com:\($0).git (fetch)\n" }.joined())
    }

    /// The URL ``remotesOutput(_:)`` lists for `origin`, as the repository's own configuration holds it.
    private nonisolated static let remotes = ["origin": "git@example.com:origin.git"]

    @Test
    func `fetch sends git fetch under the networking isolation for the primary remote`() async throws {
        let runner = FakeProcessRunner.gated(remotes: Self.remotes) { spec in
            spec.arguments.contains("fetch") ? .success("") : Self.remotesOutput()
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])

        await sut.fetch()

        let fetchSpec = try #require(runner.specs.last(where: { $0.arguments.contains("fetch") }))
        #expect(fetchSpec.arguments.contains("git@example.com:origin.git"))
        #expect(fetchSpec.environment == GitIsolation.networking.environment)
        #expect(sut.remoteNames == ["origin"])
    }

    @Test
    func `fetch refreshes repository info and calls onFetched on success`() async throws {
        let runner = FakeProcessRunner.gated(remotes: Self.remotes) { spec in
            if spec.arguments.contains("fetch") { return .success("") }
            if spec.arguments.contains("remote") { return Self.remotesOutput() }
            if spec.arguments.contains("rev-parse") { return .success(Self.root.path(percentEncoded: false)) }
            if spec.arguments.contains("for-each-ref") { return .success("main\norigin/develop\norigin/feature\n") }
            if spec.arguments.contains("log") { return .success("") }
            return .success("")
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])
        var fetchedCallCount = 0
        sut.onFetched = { fetchedCallCount += 1 }

        await sut.fetch()

        #expect(fetchedCallCount == 1)
        #expect(sut.isFetching == false)
        #expect(sut.lastFetchError == nil)
        #expect(sut.repository?.branches.contains("origin/feature") == true)
    }

    @Test
    func `fetch records the failure and leaves onFetched uncalled`() async throws {
        let runner = FakeProcessRunner.gated(remotes: Self.remotes) { spec in
            spec.arguments.contains("fetch") ? .failure(1, error: "could not resolve host") : Self.remotesOutput()
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])
        var fetchedCallCount = 0
        sut.onFetched = { fetchedCallCount += 1 }

        await sut.fetch()

        #expect(fetchedCallCount == 0)
        #expect(sut.isFetching == false)
        #expect(sut.lastFetchError?.contains("could not resolve host") == true)
    }

    @Test
    func `a second fetch while one is running does nothing`() async throws {
        let started = AsyncProbe<Void>()
        let gate = AsyncProbe<Void>()
        let runner = FakeProcessRunner.gated(remotes: Self.remotes) { spec in
            if spec.arguments.contains("fetch") {
                started.send(())
                _ = try await gate.next()
                return .success("")
            }
            return Self.remotesOutput()
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])

        let first = Task { await sut.fetch() }
        // The runner has the fetch spec in hand, so `isFetching` is certainly set.
        _ = try await started.expectNext()

        await sut.fetch()
        let fetchCallsWhileFirstWasRunning = runner.specs.count(where: { $0.arguments.contains("fetch") })

        gate.send(())
        try await first.expectValue()

        #expect(fetchCallsWhileFirstWasRunning == 1)
    }

    @Test
    func `fetch does nothing without a repository or a SourceLoader-backed reader`() async {
        let runner = FakeProcessRunner(always: .success(""))
        let sut = makeSUT(runner: runner)

        await sut.fetch()

        #expect(runner.specs.isEmpty)
        #expect(sut.isFetching == false)
    }

    @Test
    func `loadRemotesIfNeeded reads remotes once and is a no-op once known`() async throws {
        let runner = FakeProcessRunner.gated { _ in Self.remotesOutput(["origin", "upstream"]) }
        let taskProvider = TaskProviderSpy.tolerant()
        let sut = makeSUT(runner: runner, taskProvider: taskProvider)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])

        sut.loadRemotesIfNeeded()
        try await taskProvider.waitForAllTasks()

        #expect(sut.remoteNames == ["origin", "upstream"])
        #expect(runner.commandSpecs.count == 1)

        sut.loadRemotesIfNeeded()
        try await taskProvider.waitForAllTasks()

        #expect(runner.commandSpecs.count == 1)
    }

    @Test
    func `loadRemotesIfNeeded asks a repository without a remote once`() async throws {
        let runner = FakeProcessRunner.gated { _ in .success("") }
        let taskProvider = TaskProviderSpy.tolerant()
        let sut = makeSUT(runner: runner, taskProvider: taskProvider)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])

        sut.loadRemotesIfNeeded()
        try await taskProvider.waitForAllTasks()
        sut.loadRemotesIfNeeded()
        try await taskProvider.waitForAllTasks()

        #expect(sut.remoteNames.isEmpty)
        #expect(runner.commandSpecs.count == 1)
    }

    @Test
    func `fetch never publishes remote names read for a repository this side has since moved away from`()
        async throws
    {
        let started = AsyncProbe<Void>()
        let gate = AsyncProbe<Void>()
        let runner = FakeProcessRunner.gated { spec in
            if spec.arguments.contains("remote") {
                started.send(())
                _ = try await gate.next()
                return Self.remotesOutput(["origin"])
            }
            return .success("")
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])

        let fetchTask = Task { await sut.fetch() }
        // The `remotes()` read is in flight against the first repository once the runner has its spec.
        _ = try await started.expectNext()

        let otherRoot = URL(filePath: "/other", directoryHint: .isDirectory)
        let otherInfo = RepositoryInfo(root: otherRoot, branches: [], tags: [], commits: [])
        sut.load(.directory(otherRoot), repository: otherInfo, entries: [])

        gate.send(())
        try await fetchTask.expectValue()

        // The remotes read for the old repository must never land on the side that has since moved to another.
        #expect(sut.repository?.root == otherRoot)
        #expect(sut.remoteNames.isEmpty)
    }

    @Test
    func `switching the side to a different repository forgets the previous fetch state`() async throws {
        let runner = FakeProcessRunner.gated(remotes: Self.remotes) { spec in
            spec.arguments.contains("fetch") ? .failure(1, error: "no route to host") : Self.remotesOutput()
        }
        let sut = makeSUT(runner: runner)
        sut.load(.directory(Self.root), repository: Self.info, entries: [])
        await sut.fetch()
        #expect(sut.lastFetchError != nil)

        let otherRoot = URL(filePath: "/other", directoryHint: .isDirectory)
        let otherInfo = RepositoryInfo(root: otherRoot, branches: [], tags: [], commits: [])
        sut.load(.directory(otherRoot), repository: otherInfo, entries: [])

        #expect(sut.lastFetchError == nil)
        #expect(sut.remoteNames.isEmpty)
    }
}
