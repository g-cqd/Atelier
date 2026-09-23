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
        { [self] location in
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
        return try #require(SourceKitLSPRegistry.canonicalRoot(root))
    }

    deinit { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
struct LanguageServerPolicyTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.lspPolicy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

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
        let defaults = try makeDefaults()
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
        let defaults = try makeDefaults()
        setAppWideLocation(ToolLocation(isEnabled: false), defaults: defaults)
        let pinned = ToolLocation(isEnabled: true, customPath: "/opt/sourcekit-lsp")
        setProjectLocation(pinned, root: root, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [root])

        #expect(policy.sourceKitLSPLocation(forRoot: root) == pinned)
        #expect(await policy.configuration(forRoot: root) != nil)
    }

    @Test
    func `a folder inside a repository reads its repository's override`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let folder = root.appending(path: "Sources/Feature", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = try makeDefaults()
        setProjectLocation(ToolLocation(isEnabled: false), root: root, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [root, folder])

        #expect(policy.sourceKitLSPLocation(forRoot: folder)?.isEnabled == false)
        #expect(await policy.configuration(forRoot: folder) == nil)
    }

    @Test
    func `a project without an override, or a folder outside every repository, reads the app-wide value`() throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let outside = try #require(SourceKitLSPRegistry.canonicalRoot(repositories.parent))
        let defaults = try makeDefaults()
        let appWide = ToolLocation(isEnabled: true, customPath: "/opt/sourcekit-lsp")
        setAppWideLocation(appWide, defaults: defaults)
        let policy = try makePolicy(defaults: defaults, locate: LocateSpy().locate, trusting: [])

        #expect(policy.sourceKitLSPLocation(forRoot: root) == appWide)
        #expect(policy.sourceKitLSPLocation(forRoot: outside) == appWide)
    }

    @Test
    func `the SDK tier honours only the app-wide value`() async throws {
        let repositories = try ScratchRepositories()
        let root = try repositories.repository("project")
        let defaults = try makeDefaults()
        setProjectLocation(ToolLocation(isEnabled: false), root: root, defaults: defaults)
        let spy = LocateSpy()
        let policy = try makePolicy(defaults: defaults, locate: spy.locate, trusting: [])

        #expect(await policy.sdkServerExecutable() == LocateSpy.executable)

        setAppWideLocation(ToolLocation(isEnabled: false), defaults: defaults)
        #expect(await policy.sdkServerExecutable() == nil)
        #expect(spy.requestCount == 1)
    }
}
