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

/// The admission answers a test scripts, and every root it was asked about.
private actor AdmissionScript {
    private(set) var askedRoots: [URL] = []
    private var admitted: Bool

    init(admitted: Bool) {
        self.admitted = admitted
    }

    func setAdmitted(_ value: Bool) {
        admitted = value
    }

    func admits(_ root: URL) -> Bool {
        askedRoots.append(root)
        return admitted
    }
}

/// A private scratch directory standing in for a workspace root, since the registry only admits roots that exist.
/// Removed when the test releases it.
private final class ScratchRoot: Sendable {
    let directory = TemporaryDirectory(prefix: "atelier-lsp-registry")

    var url: URL { URL(filePath: directory.path, directoryHint: .isDirectory) }

    /// A subdirectory created under the scratch root.
    func subdirectory(_ name: String) throws -> URL {
        let url = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    deinit { directory.cleanup() }
}

private func makeRegistry(
    spy: ConfigurationSpy, admission: AdmissionScript = AdmissionScript(admitted: true)
) -> SourceKitLSPRegistry {
    SourceKitLSPRegistry(
        admits: { root in await admission.admits(root) },
        makeConfiguration: { root in await spy.makeConfiguration(for: root) })
}

@Suite struct SourceKitLSPRegistryTests {
    @Test func sameRootReturnsTheSameInstance() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)

        let first = await registry.service(forRoot: scratch.url)
        let second = await registry.service(forRoot: scratch.url)

        #expect(first != nil)
        #expect(first === second)
        #expect(await spy.callCount == 1)
    }

    @Test func distinctRootsGetDistinctInstances() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)

        let serviceA = await registry.service(forRoot: try scratch.subdirectory("workspace-a"))
        let serviceB = await registry.service(forRoot: try scratch.subdirectory("workspace-b"))

        #expect(serviceA != nil)
        #expect(serviceB != nil)
        #expect(serviceA !== serviceB)
        #expect(await spy.callCount == 2)
    }

    @Test func nilConfigurationIsCachedRatherThanReResolved() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        await spy.setResolves(false)
        let registry = makeRegistry(spy: spy)

        let first = await registry.service(forRoot: scratch.url)
        let second = await registry.service(forRoot: scratch.url)

        #expect(first == nil)
        #expect(second == nil)
        #expect(await spy.callCount == 1)
    }

    @Test func concurrentFirstRequestsForTheSameRootShareOneInitialization() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = SourceKitLSPRegistry(
            admits: { _ in true },
            makeConfiguration: { root in
                // Only the first caller gets here; `spy.callCount` below catches a second initialization.
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })
        let root = scratch.url

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
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)

        let first = await registry.service(forRoot: scratch.url)
        #expect(first != nil)
        await registry.shutdownAll()

        let second = await registry.service(forRoot: scratch.url)
        #expect(second != nil)
        #expect(first !== second)
        #expect(await spy.callCount == 2)
    }

    // MARK: - Canonical roots

    @Test
    func `a root with and without its trailing slash shares one session`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)
        let withSlash = URL(filePath: scratch.directory.path + "/", directoryHint: .isDirectory)
        let withoutSlash = URL(filePath: scratch.directory.path, directoryHint: .notDirectory)

        let first = await registry.service(forRoot: withSlash)
        let second = await registry.service(forRoot: withoutSlash)

        #expect(first != nil)
        #expect(first === second)
        #expect(await spy.callCount == 1)
    }

    @Test
    func `a root reached through a symbolic link shares its target's session and is configured by its real path`()
        async throws
    {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)
        let target = try scratch.subdirectory("real")
        let link = scratch.url.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let throughLink = await registry.service(forRoot: link)
        let direct = await registry.service(forRoot: target)

        #expect(throughLink != nil)
        #expect(throughLink === direct)
        let configured = try #require(await spy.roots.first)
        #expect(configured == SourceKitLSPRegistry.canonicalRoot(target))
    }

    @Test
    func `a root that names no existing directory gets no session and is never asked about`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let registry = makeRegistry(spy: spy, admission: admission)
        let missing = scratch.url.appending(path: "missing", directoryHint: .isDirectory)

        let service = await registry.service(forRoot: missing)

        #expect(service == nil)
        #expect(await admission.askedRoots.isEmpty)
        #expect(await spy.callCount == 0)
    }

    @Test
    func `the canonical root of a file is nil`() throws {
        let scratch = ScratchRoot()
        let file = scratch.url.appending(path: "file.swift")
        try Data("let x = 1\n".utf8).write(to: file)

        #expect(SourceKitLSPRegistry.canonicalRoot(file) == nil)
        #expect(SourceKitLSPRegistry.canonicalRoot(try #require(URL(string: "https://example.com/repo"))) == nil)
    }

    // MARK: - Admission

    @Test
    func `a refused root never reaches the configuration factory and is not cached`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: false)
        let registry = makeRegistry(spy: spy, admission: admission)

        let refused = await registry.service(forRoot: scratch.url)
        #expect(refused == nil)
        #expect(await spy.callCount == 0)

        await admission.setAdmitted(true)
        let admitted = await registry.service(forRoot: scratch.url)
        #expect(admitted != nil)
        #expect(await spy.callCount == 1)
    }

    @Test
    func `a root that loses its admission gets no cached session`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let registry = makeRegistry(spy: spy, admission: admission)
        let first = await registry.service(forRoot: scratch.url)
        #expect(first != nil)

        await admission.setAdmitted(false)
        let second = await registry.service(forRoot: scratch.url)

        #expect(second == nil)
    }

    @Test
    func `a root that loses its admission during its initialization publishes nothing`() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = SourceKitLSPRegistry(
            admits: { root in await admission.admits(root) },
            makeConfiguration: { root in
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })

        async let pending = registry.service(forRoot: scratch.url)
        try await entered.wait()
        await admission.setAdmitted(false)
        gate.open()
        #expect(await pending == nil)

        // Nothing was cached: once admitted again, the root initializes afresh.
        await admission.setAdmitted(true)
        #expect(await registry.service(forRoot: scratch.url) != nil)
        #expect(await spy.callCount == 2)
    }

    // MARK: - Per-root shutdown

    @Test
    func `shutting one root down forgets only that root`() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)
        let rootA = try scratch.subdirectory("workspace-a")
        let rootB = try scratch.subdirectory("workspace-b")
        let firstA = await registry.service(forRoot: rootA)
        let firstB = await registry.service(forRoot: rootB)

        await registry.shutdown(root: rootA)

        let secondA = await registry.service(forRoot: rootA)
        let secondB = await registry.service(forRoot: rootB)
        #expect(secondA != nil)
        #expect(secondA !== firstA)
        #expect(secondB === firstB)
        #expect(await spy.callCount == 3)
    }

    @Test
    func `shutting a root down during its initialization answers its waiters with nil and publishes nothing`()
        async throws
    {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = SourceKitLSPRegistry(
            admits: { _ in true },
            makeConfiguration: { root in
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })

        async let pending = registry.service(forRoot: scratch.url)
        try await entered.wait()
        await registry.shutdown(root: scratch.url)
        gate.open()

        #expect(await pending == nil)
        #expect(await registry.service(forRoot: scratch.url) != nil)
        #expect(await spy.callCount == 2)
    }
}
