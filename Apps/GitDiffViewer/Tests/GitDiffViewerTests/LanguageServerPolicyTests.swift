import AtelierDiagnostics
import AtelierLSP
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// Records every location the policy asks to be located, and answers with a fixed executable.
private final class LocateSpy: Sendable {
    private let requests = Mutex<[ToolLocation?]>([])
    static let executable = URL(filePath: "/usr/bin/true")

    var requestCount: Int { requests.withLock(\.count) }

    var locate: LanguageServerPolicy.Locate {
        { [self] _, location in
            requests.withLock { $0.append(location) }
            return Self.executable
        }
    }
}

/// Scratch directories that stand in for repositories: each holds a `.git` directory, as a work tree does.
private final class ScratchRepositories {
    let parent: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory.appending(
            path: "gdv-lsp-policy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    }

    /// A new repository named `name`, by its canonical path, as git reports a work tree's top level.
    func repository(_ name: String) throws -> URL {
        let root = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: ".git", directoryHint: .isDirectory), withIntermediateDirectories: true)
        return try #require(LanguageServerRegistry.canonicalRoot(root))
    }

    deinit { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
struct LanguageServerPolicyTests {
    private let scratchDefaults = ScratchDefaults(tag: "lspPolicy")

    /// Writes `location` as the project at `root` would through its window's settings, the way Settings writes it.
    private func setProjectLocation(_ location: ToolLocation, root: URL, defaults: UserDefaults) {
        let settings = ViewerSettings(defaults: defaults)
        settings.adoptProject(ProjectIdentity(root: root))
        settings.lspServerLocations = [LanguageServerPolicy.serverID: location]
    }

    private func setAppWideLocation(_ location: ToolLocation, defaults: UserDefaults) {
        ViewerSettings(defaults: defaults).lspServerLocations = [LanguageServerPolicy.serverID: location]
    }

    /// A policy over `defaults` whose user trusts every one of `roots`, as answering their prompts does.
    private func makePolicy(
        defaults: UserDefaults, locate: @escaping LanguageServerPolicy.Locate, trusting roots: [URL]
    ) throws -> LanguageServerPolicy {
        let trust = RepositoryTrust(defaults: defaults)
        for root in roots {
            trust.requestTrust(for: root)
            trust.answer(try #require(trust.claimNextRequest()), trusts: true)
        }
        return LanguageServerPolicy(trust: trust, defaults: defaults, locate: locate)
    }

    @Test
    func `a project-level disable stops the launch for that project only`() async throws {
        let repositories = try ScratchRepositories()
        let disabled = try repositories.repository("disabled")
        let other = try repositories.repository("other")
        let defaults = scratchDefaults.defaults
        setProjectLocation(ToolLocation(isEnabled: false), root: disabled, defaults: defaults)
        let spy = LocateSpy()
        let policy = try makePolicy(defaults: defaults, locate: spy.locate, trusting: [disabled, other])

        #expect(await policy.configuration(forRoot: disabled) == nil)
        #expect(spy.requestCount == 0)

        let configuration = try #require(await policy.configuration(forRoot: other))
        #expect(configuration.workspaceRoot == other)
        #expect(configuration.serverExecutable == LocateSpy.executable)
    }

    @Test
    func `a project's override wins over the app-wide value, custom path included`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let defaults = scratchDefaults.defaults
        setAppWideLocation(ToolLocation(isEnabled: false), defaults: defaults)
        let pinned = ToolLocation(isEnabled: true, customPath: "/opt/sourcekit-lsp")
        setProjectLocation(pinned, root: root, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [root])

        #expect(policy.location(of: .sourceKitLSP, forRoot: root) == pinned)
        #expect(await policy.configuration(forRoot: root) != nil)
    }

    @Test
    func `a folder inside a repository reads its repository's override`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let folder = root.appending(path: "Sources/Feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = scratchDefaults.defaults
        setProjectLocation(ToolLocation(isEnabled: false), root: root, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [root, folder])

        #expect(policy.location(of: .sourceKitLSP, forRoot: folder)?.isEnabled == false)
        #expect(await policy.configuration(forRoot: folder) == nil)
    }

    @Test
    func `a project without an override, or a folder outside every repository, reads the app-wide value`() throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let outside = try #require(LanguageServerRegistry.canonicalRoot(repositories.parent))
        let defaults = scratchDefaults.defaults
        let appWide = ToolLocation(isEnabled: true, customPath: "/opt/sourcekit-lsp")
        setAppWideLocation(appWide, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [])

        #expect(policy.location(of: .sourceKitLSP, forRoot: root) == appWide)
        #expect(policy.location(of: .sourceKitLSP, forRoot: outside) == appWide)
    }

    @Test
    func `the SDK tier honours only the app-wide value`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let defaults = scratchDefaults.defaults
        setProjectLocation(ToolLocation(isEnabled: false), root: root, defaults: defaults)
        let spy = LocateSpy()
        let policy = try makePolicy(defaults: defaults, locate: spy.locate, trusting: [])

        #expect(await policy.sdkServerExecutable() == LocateSpy.executable)

        setAppWideLocation(ToolLocation(isEnabled: false), defaults: defaults)
        #expect(await policy.sdkServerExecutable() == nil)
        #expect(spy.requestCount == 1)
    }

    // MARK: - Every server

    @Test
    func `each server has its own location, and runs with its own arguments and environment`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let defaults = scratchDefaults.defaults
        ViewerSettings(defaults: defaults).lspServerLocations = [
            LanguageServerDescriptor.gopls.id: ToolLocation(isEnabled: false),
            LanguageServerDescriptor.typeScriptLanguageServer.id: ToolLocation(customPath: "/opt/tsls")
        ]
        let asked = Mutex<[String]>([])
        let trust = RepositoryTrust(defaults: defaults)
        trust.requestTrust(for: root)
        trust.answer(try #require(trust.claimNextRequest()), trusts: true)
        let policy = LanguageServerPolicy(
            trust: trust, defaults: defaults,
            locate: { server, location in
                asked.withLock { $0.append(server.id) }
                return location?.customPath.map { URL(filePath: $0) } ?? LocateSpy.executable
            },
            environment: { server, _ in server.runtimeExecutableName.map { ["PATH": "/\($0)/bin"] } })

        #expect(await policy.configuration(forRoot: root, server: .gopls) == nil)
        let typeScript = try #require(await policy.configuration(forRoot: root, server: .typeScriptLanguageServer))
        let swift = try #require(await policy.configuration(forRoot: root, server: .sourceKitLSP))

        #expect(asked.withLock { $0 } == ["typescript-language-server", "sourcekit-lsp"])
        #expect(typeScript.serverExecutable == URL(filePath: "/opt/tsls"))
        #expect(typeScript.serverArguments == ["--stdio"])
        #expect(typeScript.environment == ["PATH": "/node/bin"])
        #expect(swift.serverExecutable == LocateSpy.executable)
        #expect(swift.environment == nil)
        #expect(!policy.admitsSession(at: root, server: .gopls))
        #expect(policy.admitsSession(at: root, server: .typeScriptLanguageServer))
    }

    @Test
    func `a root a server's markers find inside a repository is gated by the repository's trust`() async throws {
        let repositories = try ScratchRepositories()
        let trusted = try repositories.repository("trusted")
        let undecided = try repositories.repository("undecided")
        func nested(_ repository: URL) throws -> URL {
            let web = repository.appending(path: "packages/web", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
            return try #require(LanguageServerRegistry.canonicalRoot(web))
        }
        let trustedWeb = try nested(trusted)
        let undecidedWeb = try nested(undecided)
        let defaults = scratchDefaults.defaults
        let trust = RepositoryTrust(defaults: defaults)
        trust.requestTrust(for: trusted)
        trust.answer(try #require(trust.claimNextRequest()), trusts: true)
        let policy = LanguageServerPolicy(trust: trust, defaults: defaults, locate: LocateSpy().locate)

        #expect(policy.admitsSession(at: trustedWeb, server: .typeScriptLanguageServer))
        #expect(await policy.configuration(forRoot: trustedWeb, server: .typeScriptLanguageServer) != nil)
        #expect(trust.nextRequest == nil)

        #expect(!policy.admitsSession(at: undecidedWeb, server: .typeScriptLanguageServer))
        #expect(await policy.configuration(forRoot: undecidedWeb, server: .typeScriptLanguageServer) == nil)
        #expect(trust.nextRequest?.root == undecided)
    }
}
