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
        let service = SourceKitLSPService(
            configuration: SourceKitLSPService.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/false"), workspaceRoot: probeDirectory))
        return SDKHoverTier.Resolved(
            provider: SDKDocumentationProvider(service: service), probeDirectory: probeDirectory)
    }

    deinit { try? FileManager.default.removeItem(at: probeDirectory) }
}

@MainActor
struct SDKHoverTierTests {
    @Test
    func `two concurrent first calls share one resolution and one scratch session`() async throws {
        let spy = try ResolutionSpy()
        let tier = SDKHoverTier(taskProvider: TaskProviderSpy.tolerant()) { await spy.resolve() }

        async let first = tier.provider()
        try await spy.entered.expectOpen()
        // The first resolution is suspended inside its own work: a second call must join it, not start another.
        async let second = tier.provider()
        spy.gate.open()
        let (firstProvider, secondProvider) = await (first, second)

        #expect(spy.resolutions == 1)
        #expect(firstProvider != nil)
        #expect(firstProvider === secondProvider)
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
