import AemiTestKit
import Foundation
import Testing

@testable import AtelierLSP

/// Counts how many times the registry's configuration factory was actually invoked, and can be scripted to
/// return `nil` for some roots (as if no executable could be resolved there).
private actor ConfigurationSpy {
    private(set) var callCount = 0
    private(set) var roots: [URL] = []
    private var resolves = true

    func setResolves(_ value: Bool) {
        resolves = value
    }

    func makeConfiguration(for root: URL) -> SourceKitLSPService.Configuration? {
        callCount += 1
        roots.append(root)
        guard resolves else { return nil }
        return SourceKitLSPService.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/true"), workspaceRoot: root)
    }
}

@Suite struct SourceKitLSPRegistryTests {
    @Test func sameRootReturnsTheSameInstance() async {
        let spy = ConfigurationSpy()
        let registry = SourceKitLSPRegistry { root in await spy.makeConfiguration(for: root) }
        let root = URL(filePath: "/tmp/workspace-a")

        let first = await registry.service(forRoot: root)
        let second = await registry.service(forRoot: root)

        #expect(first != nil)
        #expect(first === second)
        #expect(await spy.callCount == 1)
    }

    @Test func distinctRootsGetDistinctInstances() async {
        let spy = ConfigurationSpy()
        let registry = SourceKitLSPRegistry { root in await spy.makeConfiguration(for: root) }
        let rootA = URL(filePath: "/tmp/workspace-a")
        let rootB = URL(filePath: "/tmp/workspace-b")

        let serviceA = await registry.service(forRoot: rootA)
        let serviceB = await registry.service(forRoot: rootB)

        #expect(serviceA != nil)
        #expect(serviceB != nil)
        #expect(serviceA !== serviceB)
        #expect(await spy.callCount == 2)
    }

    @Test func nilConfigurationIsCachedRatherThanReResolved() async {
        let spy = ConfigurationSpy()
        await spy.setResolves(false)
        let registry = SourceKitLSPRegistry { root in await spy.makeConfiguration(for: root) }
        let root = URL(filePath: "/tmp/workspace-unresolvable")

        let first = await registry.service(forRoot: root)
        let second = await registry.service(forRoot: root)

        #expect(first == nil)
        #expect(second == nil)
        #expect(await spy.callCount == 1)
    }

    @Test func concurrentFirstRequestsForTheSameRootShareOneInitialization() async throws {
        let spy = ConfigurationSpy()
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = SourceKitLSPRegistry { root in
            // Only the winning first caller ever reaches here; a duplicate-initialization bug would call
            // this twice concurrently, which `spy.callCount` below would then catch as 2 instead of 1.
            entered.open()
            try? await gate.wait()
            return await spy.makeConfiguration(for: root)
        }
        let root = URL(filePath: "/tmp/workspace-concurrent")

        async let first = registry.service(forRoot: root)
        async let second = registry.service(forRoot: root)

        try await entered.wait()
        gate.open()

        let (firstService, secondService) = await (first, second)
        #expect(firstService != nil)
        #expect(firstService === secondService)
        #expect(await spy.callCount == 1)
    }

    @Test func shutdownAllForwardsAndClearsTheTable() async {
        let spy = ConfigurationSpy()
        let registry = SourceKitLSPRegistry { root in await spy.makeConfiguration(for: root) }
        let root = URL(filePath: "/tmp/workspace-shutdown")

        let first = await registry.service(forRoot: root)
        #expect(first != nil)
        await registry.shutdownAll()

        let second = await registry.service(forRoot: root)
        #expect(second != nil)
        #expect(first !== second)
        #expect(await spy.callCount == 2)
    }
}
