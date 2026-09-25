import AemiTesting
import AtelierDiagnostics
import AtelierLSP
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// Stands in for the language-server factory: records every root that reaches it, and answers with a session that
/// is never started, so no server process runs.
private final class FactorySpy: Sendable {
    private let recorded = Mutex<[URL]>([])

    var roots: [URL] { recorded.withLock { $0 } }

    func configuration(forRoot root: URL) -> LanguageServerSession.Configuration {
        recorded.withLock { $0.append(root) }
        return LanguageServerSession.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/false"), workspaceRoot: root)
    }
}

/// A repository root on disk and the app's trust gate over it, wired as `AppServices` wires them.
@MainActor
private struct TrustGate {
    let root: URL
    let trust: RepositoryTrust
    let policy: LanguageServerPolicy
    let registry: LanguageServerRegistry
    let factory = FactorySpy()
    let tasks = TaskProviderSpy.tolerant()
    /// The suite the trust decisions and the settings persist to, removed with the gate.
    private let scratchDefaults = ScratchDefaults(tag: "trustGate")

    /// - Parameter appWideLocation: sourcekit-lsp's app-wide setting, written as Settings writes it.
    /// - Throws: When the root cannot be created.
    init(appWideLocation: ToolLocation? = nil) throws {
        let defaults = scratchDefaults.defaults
        if let appWideLocation {
            ViewerSettings(defaults: defaults).lspServerLocations = [LanguageServerPolicy.serverID: appWideLocation]
        }
        root = FileManager.default.temporaryDirectory.appending(path: "gdv-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appending(path: ".git", directoryHint: .isDirectory), withIntermediateDirectories: true)
        trust = RepositoryTrust(defaults: defaults)
        let policy = LanguageServerPolicy(
            trust: trust, defaults: defaults, locate: { _, _ in URL(filePath: "/usr/bin/false") }, taskProvider: tasks)
        let factory = factory
        registry = LanguageServerRegistry(
            admits: { root, _ in await policy.admitsSession(at: root) },
            makeConfiguration: { root, _ in
                guard await policy.configuration(forRoot: root) != nil else { return nil }
                return factory.configuration(forRoot: root)
            })
        policy.stopSessionsOnRevocation(in: registry)
        self.policy = policy
    }

    var canonicalRoot: URL? { LanguageServerRegistry.canonicalRoot(root) }

    func trustRoot() throws {
        trust.requestTrust(for: root)
        trust.answer(try #require(trust.claimNextRequest()), trusts: true)
    }

    func removeRoot() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
@Suite(.mainActorLane)
struct LanguageServerTrustGateTests {
    private let documented = """
        /// Adds two numbers.
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        """

    @Test
    func `an untrusted root never reaches the language-server factory, and hover still answers from the doc index`()
        async throws
    {
        let gate = try TrustGate()
        defer { gate.removeRoot() }
        let model = HoverDocumentationModel(lspRegistry: gate.registry, taskProvider: gate.tasks)
        model.comparisonChanged(
            root: gate.root,
            files: [
                HoverDocumentationModel.FileEntry(
                    index: 0, leftPath: "Sources/Math.swift", rightPath: "Sources/Math.swift", oldText: documented,
                    newText: documented, oldBlobID: "old", newBlobID: "new")
            ])
        try await gate.tasks.waitForAllTasks()

        let content = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)

        #expect(gate.factory.roots.isEmpty)
        #expect(content?.source == .docIndex)
        #expect(content?.markdown.contains("Adds two numbers.") == true)
    }

    @Test
    func `a hover in an unknown repository asks the user once`() async throws {
        let gate = try TrustGate()
        defer { gate.removeRoot() }

        #expect(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP) == nil)
        #expect(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP) == nil)

        let request = try #require(gate.trust.claimNextRequest())
        #expect(request.root == gate.canonicalRoot)
        #expect(gate.trust.nextRequest == nil)
    }

    @Test
    func `a declined repository neither starts a session nor asks again`() async throws {
        let gate = try TrustGate()
        defer { gate.removeRoot() }
        _ = await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP)
        gate.trust.answer(try #require(gate.trust.claimNextRequest()), trusts: false)

        #expect(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP) == nil)
        #expect(gate.factory.roots.isEmpty)
        #expect(gate.trust.nextRequest == nil)
    }

    @Test
    func `a trusted repository starts its session at its canonical root`() async throws {
        let gate = try TrustGate()
        defer { gate.removeRoot() }
        try gate.trustRoot()

        let service = try #require(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP))

        #expect(gate.factory.roots == [try #require(gate.canonicalRoot)])
        #expect(service.workspaceRoot == gate.canonicalRoot)
    }

    @Test
    func `revoking trust stops the running session and every new one`() async throws {
        let gate = try TrustGate()
        defer { gate.removeRoot() }
        try gate.trustRoot()
        let running = try #require(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP))

        gate.trust.revoke(gate.root)
        try await gate.tasks.waitForAllTasks()

        #expect(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP) == nil)
        // Trusted again, the root starts afresh: the revocation forgot the running session.
        try gate.trustRoot()
        let restarted = try #require(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP))
        #expect(restarted !== running)
        #expect(gate.factory.roots.count == 2)
    }

    @Test
    func `a repository where sourcekit-lsp is off asks nothing`() async throws {
        let gate = try TrustGate(appWideLocation: ToolLocation(isEnabled: false))
        defer { gate.removeRoot() }

        #expect(await gate.registry.session(forRoot: gate.root, server: .sourceKitLSP) == nil)

        #expect(gate.trust.nextRequest == nil)
        #expect(gate.factory.roots.isEmpty)
    }
}
