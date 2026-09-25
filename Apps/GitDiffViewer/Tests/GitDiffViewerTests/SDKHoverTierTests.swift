import AemiTesting
import AtelierLSP
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// Counts the resolutions a tier runs and holds each one until the test opens its gate.
private final class ResolutionSpy: Sendable {
    private let count = Mutex(0)
    let gate = TaskGate()
    let entered = TaskGate()
    let probeDirectory: URL

    init() throws {
        probeDirectory = try SDKDocumentationProvider.makeProbeDirectory()
    }

    var resolutions: Int { count.withLock { $0 } }

    /// One resolution: a scratch session over the probe directory that is never started, so no server runs.
    func resolve() async -> SDKHoverTier.Resolved? {
        count.withLock { $0 += 1 }
        entered.open()
        try? await gate.wait()
        let service = LanguageServerSession(
            configuration: LanguageServerSession.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/false"), workspaceRoot: probeDirectory))
        return SDKHoverTier.Resolved(
            provider: SDKDocumentationProvider(service: service), probeDirectory: probeDirectory)
    }

    deinit { try? FileManager.default.removeItem(at: probeDirectory) }
}

@MainActor
@Suite(.mainActorLane)
struct SDKHoverTierTests {
    /// Calls a fresh tier twice, the second call once `awaitingEntry` has seen the first one's resolution start, and
    /// returns both calls' providers.
    ///
    /// The calls are tasks awaited within the failure bound, and the gate opens on every way out: a call waits on the
    /// resolution, which waits on the gate, so an `async let` call would be awaited forever once `awaitingEntry` threw.
    private func twoConcurrentFirstCalls(
        _ spy: ResolutionSpy, awaitingEntry: @Sendable () async throws -> Void
    ) async throws -> (first: SDKDocumentationProvider?, second: SDKDocumentationProvider?) {
        let tier = SDKHoverTier(taskProvider: TaskProviderSpy.tolerant()) { await spy.resolve() }
        defer { spy.gate.open() }
        let first = Task { await tier.provider() }
        try await awaitingEntry()
        // The first resolution is suspended inside its own work: a second call must join it, not start another.
        let second = Task { await tier.provider() }
        spy.gate.open()
        return (try await first.expectValue(), try await second.expectValue())
    }

    @Test
    func `two concurrent first calls share one resolution and one scratch session`() async throws {
        let spy = try ResolutionSpy()

        let (firstProvider, secondProvider) = try await twoConcurrentFirstCalls(spy) {
            try await spy.entered.expectOpen()
        }

        #expect(spy.resolutions == 1)
        #expect(firstProvider != nil)
        #expect(firstProvider === secondProvider)
    }

    /// A main actor held past the failure bound, as a loaded machine can, fails the wait for the first resolution; the
    /// test must then fail with that wait's error, not wait forever on a call the unopened gate holds.
    @Test
    func `a failed wait for the first resolution ends the two calls instead of hanging them`() async throws {
        struct EntryNotSeen: Error {}
        let spy = try ResolutionSpy()

        let failedWithTheWait = try await withFailureBound(awaiting: "The two calls' end after a failed wait") {
            do {
                _ = try await twoConcurrentFirstCalls(spy) { throw EntryNotSeen() }
                return false
            } catch is EntryNotSeen {
                return true
            }
        }

        #expect(failedWithTheWait)
    }

    @Test
    func `a tier that resolved to nothing is not resolved again`() async {
        let calls = Mutex(0)
        let tier = SDKHoverTier(taskProvider: TaskProviderSpy.tolerant()) {
            calls.withLock { $0 += 1 }
            return nil
        }

        #expect(await tier.provider() == nil)
        #expect(await tier.provider() == nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test
    func `shutting the tier down removes its probe directory`() async throws {
        let spy = try ResolutionSpy()
        spy.gate.open()
        let tier = SDKHoverTier(taskProvider: TaskProviderSpy.tolerant()) { await spy.resolve() }
        _ = await tier.provider()

        await tier.shutdown()

        #expect(!FileManager.default.fileExists(atPath: spy.probeDirectory.path(percentEncoded: false)))
    }

    @Test
    func `shutting down a tier nobody asked for resolves nothing`() async throws {
        let spy = try ResolutionSpy()
        let tier = SDKHoverTier(taskProvider: TaskProviderSpy.tolerant()) { await spy.resolve() }

        await tier.shutdown()

        #expect(spy.resolutions == 0)
    }
}
