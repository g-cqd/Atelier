import AemiTesting
import AtelierDiagnostics
import AtelierLSP
import AtelierSyntaxModel
import DiffGit
import DiffRendering
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

    /// Records `root` and resolves no session, for a caller that would start the one it gets.
    func noConfiguration(forRoot root: URL) -> LanguageServerSession.Configuration? {
        recorded.withLock { $0.append(root) }
        return nil
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

    /// - Parameters:
    ///   - appWideLocation: sourcekit-lsp's app-wide setting, written as Settings writes it.
    ///   - resolvesSessions: Whether a root that reaches the factory gets a session; without, the factory records the
    ///     root and resolves none, for a caller that asks the server something, which would start it.
    /// - Throws: When the root cannot be created.
    init(appWideLocation: ToolLocation? = nil, resolvesSessions: Bool = true) throws {
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
                return resolvesSessions ? factory.configuration(forRoot: root) : factory.noConfiguration(forRoot: root)
            })
        policy.stopSessionsOnRevocation(in: registry)
        self.policy = policy
    }

    var canonicalRoot: URL? { LanguageServerRegistry.canonicalRoot(root) }

    func trustRoot() throws {
        trust.requestTrust(for: root)
        trust.answer(try #require(trust.claimNextRequest()), trusts: true)
    }

    /// Trusts a repository of its own, apart from ``root``, which it removes at once; a request for ``root`` stays.
    func trustAnotherRepository() throws {
        let other = FileManager.default.temporaryDirectory.appending(path: "gdv-gate-other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: other) }
        let canonical = try #require(LanguageServerRegistry.canonicalRoot(other))
        trust.answer(RepositoryTrust.Request(root: canonical), trusts: true)
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

    // MARK: - Asking again once trusted

    @Test
    func `a hover refused before the user trusts the repository asks its language server once they do`()
        async throws
    {
        let gate = try TrustGate(resolvesSessions: false)
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
        _ = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)
        #expect(gate.factory.roots.isEmpty)

        gate.trust.answer(try #require(gate.trust.claimNextRequest()), trusts: true)
        let content = await model.hover(fileIndex: 0, side: .new, line: 1, utf16Column: 6)

        #expect(gate.factory.roots == [try #require(gate.canonicalRoot)])
        #expect(content?.markdown.contains("Adds two numbers.") == true)
    }

    /// A window's model over `gate`'s repository as its right side, holding `a.swift` changed, with the file shown and
    /// its sides refined while the repository is untrusted.
    private func showSwiftFile(in gate: TrustGate, harness: ModelTestHarness) async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        sut.attachHoverDocs(lspRegistry: gate.registry, trust: gate.trust)
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(gate.root)] = [harness.entry("a.swift", "2")]
        harness.reader.blobContents["1"] = "let a = 1\n"
        harness.reader.blobContents["2"] = "let a = 2\n"
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(gate.root), repository: nil)
        try await harness.taskProvider.waitForAllTasks()
        sut.noteDisplayed(try #require(sut.renderedFiles.first?.rendered.id))
        try await harness.taskProvider.waitForAllTasks()
        try await gate.tasks.waitForAllTasks()
        return sut
    }

    @Test
    func `trusting the repository shown asks for the shown Swift sides' semantic colour again`() async throws {
        let gate = try TrustGate(resolvesSessions: false)
        defer { gate.removeRoot() }
        let harness = ModelTestHarness()
        let sut = try await showSwiftFile(in: gate, harness: harness)
        #expect(gate.factory.roots.isEmpty)
        let asked = sut.pipeline.decorator.started

        gate.trust.answer(try #require(gate.trust.claimNextRequest()), trusts: true)
        try await harness.taskProvider.waitForAllTasks()

        #expect(gate.factory.roots == [try #require(gate.canonicalRoot)])
        #expect(sut.pipeline.decorator.started > asked)
    }

    @Test
    func `trusting another repository refines nothing again`() async throws {
        let gate = try TrustGate(resolvesSessions: false)
        defer { gate.removeRoot() }
        let harness = ModelTestHarness()
        let sut = try await showSwiftFile(in: gate, harness: harness)
        let asked = sut.pipeline.decorator.started

        try gate.trustAnotherRepository()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.pipeline.decorator.started == asked)
        #expect(gate.factory.roots.isEmpty)
    }
}
