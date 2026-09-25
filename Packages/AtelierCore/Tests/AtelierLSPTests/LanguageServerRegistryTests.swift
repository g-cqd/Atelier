import AemiTestKit
import Foundation
import Synchronization
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

    func makeConfiguration(for root: URL) -> LanguageServerSession.Configuration? {
        callCount += 1
        roots.append(root)
        guard resolves else { return nil }
        return LanguageServerSession.Configuration(
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
) -> LanguageServerRegistry {
    LanguageServerRegistry(
        admits: { root, _ in await admission.admits(root) },
        makeConfiguration: { root, _ in await spy.makeConfiguration(for: root) })
}

@Suite struct LanguageServerRegistryTests {
    @Test func sameRootReturnsTheSameInstance() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)

        let first = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        let second = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)

        #expect(first != nil)
        #expect(first === second)
        #expect(await spy.callCount == 1)
    }

    @Test func distinctRootsGetDistinctInstances() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)

        let serviceA = await registry.session(forRoot: try scratch.subdirectory("workspace-a"), server: .sourceKitLSP)
        let serviceB = await registry.session(forRoot: try scratch.subdirectory("workspace-b"), server: .sourceKitLSP)

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

        let first = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        let second = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)

        #expect(first == nil)
        #expect(second == nil)
        #expect(await spy.callCount == 1)
    }

    @Test func concurrentFirstRequestsForTheSameRootShareOneInitialization() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = LanguageServerRegistry(
            admits: { _, _ in true },
            makeConfiguration: { root, _ in
                // Only the first caller gets here; `spy.callCount` below catches a second initialization.
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })
        let root = scratch.url

        async let first = registry.session(forRoot: root, server: .sourceKitLSP)
        async let second = registry.session(forRoot: root, server: .sourceKitLSP)

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

        let first = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        #expect(first != nil)
        await registry.shutdownAll()

        let second = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
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

        let first = await registry.session(forRoot: withSlash, server: .sourceKitLSP)
        let second = await registry.session(forRoot: withoutSlash, server: .sourceKitLSP)

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

        let throughLink = await registry.session(forRoot: link, server: .sourceKitLSP)
        let direct = await registry.session(forRoot: target, server: .sourceKitLSP)

        #expect(throughLink != nil)
        #expect(throughLink === direct)
        let configured = try #require(await spy.roots.first)
        #expect(configured == LanguageServerRegistry.canonicalRoot(target))
    }

    @Test
    func `a root that names no existing directory gets no session and is never asked about`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let registry = makeRegistry(spy: spy, admission: admission)
        let missing = scratch.url.appending(path: "missing", directoryHint: .isDirectory)

        let service = await registry.session(forRoot: missing, server: .sourceKitLSP)

        #expect(service == nil)
        #expect(await admission.askedRoots.isEmpty)
        #expect(await spy.callCount == 0)
    }

    @Test
    func `the canonical root of a file is nil`() throws {
        let scratch = ScratchRoot()
        let file = scratch.url.appending(path: "file.swift")
        try Data("let x = 1\n".utf8).write(to: file)

        #expect(LanguageServerRegistry.canonicalRoot(file) == nil)
        #expect(LanguageServerRegistry.canonicalRoot(try #require(URL(string: "https://example.com/repo"))) == nil)
    }

    // MARK: - Admission

    @Test
    func `a refused root never reaches the configuration factory and is not cached`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: false)
        let registry = makeRegistry(spy: spy, admission: admission)

        let refused = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        #expect(refused == nil)
        #expect(await spy.callCount == 0)

        await admission.setAdmitted(true)
        let admitted = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        #expect(admitted != nil)
        #expect(await spy.callCount == 1)
    }

    @Test
    func `a root that loses its admission gets no cached session`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let registry = makeRegistry(spy: spy, admission: admission)
        let first = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        #expect(first != nil)

        await admission.setAdmitted(false)
        let second = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)

        #expect(second == nil)
    }

    @Test
    func `a root that loses its admission during its initialization publishes nothing`() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let admission = AdmissionScript(admitted: true)
        let gate = AsyncLatch()
        let entered = AsyncLatch()
        let registry = LanguageServerRegistry(
            admits: { root, _ in await admission.admits(root) },
            makeConfiguration: { root, _ in
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })

        async let pending = registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        try await entered.wait()
        await admission.setAdmitted(false)
        gate.open()
        #expect(await pending == nil)

        // Nothing was cached: once admitted again, the root initializes afresh.
        await admission.setAdmitted(true)
        #expect(await registry.session(forRoot: scratch.url, server: .sourceKitLSP) != nil)
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
        let firstA = await registry.session(forRoot: rootA, server: .sourceKitLSP)
        let firstB = await registry.session(forRoot: rootB, server: .sourceKitLSP)

        await registry.shutdown(root: rootA)

        let secondA = await registry.session(forRoot: rootA, server: .sourceKitLSP)
        let secondB = await registry.session(forRoot: rootB, server: .sourceKitLSP)
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
        let registry = LanguageServerRegistry(
            admits: { _, _ in true },
            makeConfiguration: { root, _ in
                entered.open()
                try? await gate.wait()
                return await spy.makeConfiguration(for: root)
            })

        async let pending = registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        try await entered.wait()
        await registry.shutdown(root: scratch.url)
        gate.open()

        #expect(await pending == nil)
        #expect(await registry.session(forRoot: scratch.url, server: .sourceKitLSP) != nil)
        #expect(await spy.callCount == 2)
    }

    // MARK: - Servers

    @Test
    func `one root runs one session per server, each configured for its own server`() async {
        let scratch = ScratchRoot()
        let configured = Mutex<[String]>([])
        let registry = LanguageServerRegistry(
            admits: { _, _ in true },
            makeConfiguration: { root, server in
                configured.withLock { $0.append(server.id) }
                return LanguageServerSession.Configuration(
                    descriptor: server, serverExecutable: URL(filePath: "/usr/bin/true"), workspaceRoot: root)
            })

        let swift = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        let go = await registry.session(forRoot: scratch.url, server: .gopls)
        let goAgain = await registry.session(forRoot: scratch.url, server: .gopls)

        #expect(swift != nil)
        #expect(go != nil)
        #expect(swift !== go)
        #expect(go === goAgain)
        #expect(configured.withLock { $0 } == ["sourcekit-lsp", "gopls"])
    }

    @Test
    func `the admission check is asked about each server`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = LanguageServerRegistry(
            admits: { _, server in server == .sourceKitLSP },
            makeConfiguration: { root, _ in await spy.makeConfiguration(for: root) })

        #expect(await registry.session(forRoot: scratch.url, server: .typeScriptLanguageServer) == nil)
        #expect(await registry.session(forRoot: scratch.url, server: .sourceKitLSP) != nil)
        #expect(await spy.callCount == 1)
    }

    @Test
    func `shutting a root down forgets every server's session there`() async {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)
        let swift = await registry.session(forRoot: scratch.url, server: .sourceKitLSP)
        let go = await registry.session(forRoot: scratch.url, server: .gopls)

        await registry.shutdown(root: scratch.url)

        #expect(await registry.session(forRoot: scratch.url, server: .sourceKitLSP) !== swift)
        #expect(await registry.session(forRoot: scratch.url, server: .gopls) !== go)
        #expect(await spy.callCount == 4)
    }

    // MARK: - Workspace roots

    /// Creates `names`, relative to the scratch root, as empty files, and their directories.
    private func touch(_ names: [String], in scratch: ScratchRoot) throws {
        for name in names {
            let url = scratch.url.appending(path: name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
    }

    @Test
    func `a document's root is the nearest directory holding its server's marker`() throws {
        let scratch = ScratchRoot()
        let ceiling = try #require(LanguageServerRegistry.canonicalRoot(scratch.url))
        try touch(["go.mod", "tools/go.mod", "tools/cmd/main.go"], in: scratch)

        let root = LanguageServerRegistry.workspaceRoot(
            forDocumentAt: ceiling.appending(path: "tools/cmd/main.go"), within: ceiling,
            markers: ["go.work", "go.mod"])

        #expect(root == ceiling.appending(path: "tools", directoryHint: .isDirectory))
    }

    @Test
    func `a stronger marker further up wins over a weaker one nearer the document`() throws {
        let scratch = ScratchRoot()
        let ceiling = try #require(LanguageServerRegistry.canonicalRoot(scratch.url))
        try touch(["web/tsconfig.json", "web/app/package.json", "web/app/src/a.ts"], in: scratch)

        let root = LanguageServerRegistry.workspaceRoot(
            forDocumentAt: ceiling.appending(path: "web/app/src/a.ts"), within: ceiling,
            markers: LanguageServerDescriptor.typeScriptLanguageServer.rootMarkers)

        #expect(root == ceiling.appending(path: "web", directoryHint: .isDirectory))
    }

    @Test
    func `without a marker, or outside the ceiling, a document's root is the ceiling`() throws {
        let scratch = ScratchRoot()
        let ceiling = try #require(LanguageServerRegistry.canonicalRoot(try scratch.subdirectory("repo")))
        try touch(["go.mod", "repo/pkg/a.go"], in: scratch)
        let document = ceiling.appending(path: "pkg/a.go")

        func root(of document: URL, markers: [String]) -> URL {
            LanguageServerRegistry.workspaceRoot(forDocumentAt: document, within: ceiling, markers: markers)
        }

        #expect(root(of: document, markers: ["go.mod"]) == ceiling)
        #expect(root(of: document, markers: []) == ceiling)
        #expect(root(of: scratch.url.appending(path: "elsewhere/a.go"), markers: ["go.mod"]) == ceiling)
    }

    @Test
    func `a document's session runs at its server's root`() async throws {
        let scratch = ScratchRoot()
        let spy = ConfigurationSpy()
        let registry = makeRegistry(spy: spy)
        try touch(["svc/go.mod", "svc/main.go"], in: scratch)
        let ceiling = try #require(LanguageServerRegistry.canonicalRoot(scratch.url))

        let go = await registry.session(
            forDocumentAt: ceiling.appending(path: "svc/main.go"), within: scratch.url, server: .gopls)
        let swift = await registry.session(
            forDocumentAt: ceiling.appending(path: "svc/main.swift"), within: scratch.url, server: .sourceKitLSP)

        #expect(go?.workspaceRoot == ceiling.appending(path: "svc", directoryHint: .isDirectory))
        #expect(swift?.workspaceRoot == ceiling)
    }
}
