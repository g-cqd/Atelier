package import AemiCore
package import AtelierDiagnostics
package import AtelierLSP
import DiffGit
package import Foundation

/// Decides whether and how GitDiffViewer launches sourcekit-lsp: per repository root for the language-server tier,
/// only where the user trusts the repository, and app-wide for the SDK tier, whose scratch session has no root.
@MainActor
package final class LanguageServerPolicy {
    /// Finds sourcekit-lsp's executable for a persisted location, honoring its custom path; nil when none resolves.
    package typealias Locate = @Sendable (ToolLocation?) async -> URL?

    /// The id sourcekit-lsp's location is stored under in ``ViewerSettings/lspServerLocations``.
    static let serverID = "sourcekit-lsp"

    private let trust: RepositoryTrust
    private let defaults: UserDefaults
    private let locate: Locate
    private let taskProvider: any TaskProvider

    /// - Parameters:
    ///   - trust: The user's decisions, which gate every session with a repository root.
    ///   - defaults: Where ``ViewerSettings`` persists `lspServerLocations`, app-wide and per project.
    ///   - locate: Finds the executable; ``locate(with:)`` in the app.
    ///   - taskProvider: Spawns the shutdown of a revoked repository's session.
    package init(
        trust: RepositoryTrust, defaults: UserDefaults = .standard, locate: @escaping Locate,
        taskProvider: any TaskProvider = .default
    ) {
        self.trust = trust
        self.defaults = defaults
        self.locate = locate
        self.taskProvider = taskProvider
    }

    /// Shuts a repository's session in `registry` down as soon as the user stops trusting the repository, rather than
    /// at its idle shutdown. The registry already refuses the root from then on; this stops the server running there.
    package func stopSessionsOnRevocation(in registry: SourceKitLSPRegistry) {
        // Weak: the registry's own closures hold this policy, which holds the trust store that holds this closure.
        trust.onDecisionChanged = { [weak registry, taskProvider] root, decision in
            guard decision == .declined, let registry else { return }
            taskProvider.task { await registry.shutdown(root: root) }
        }
    }

    /// Looks sourcekit-lsp up through `discovery` the way the Tools settings do: the `GDV_SOURCEKIT_LSP` override, the
    /// location's custom path, then the toolchain and the usual directories.
    package static func locate(with discovery: ToolDiscovery) -> Locate {
        { location in
            await discovery.locate(
                executableName: serverID, overrideVariable: "GDV_SOURCEKIT_LSP", customPath: location?.customPath,
                searchesToolchain: true)?
                .url
        }
    }

    /// Whether a sourcekit-lsp session may run at `root`, a canonical directory: sourcekit-lsp is on for `root`'s
    /// project, and the user trusts the repository. A root the user never decided on is refused and asks the user,
    /// once; a root where sourcekit-lsp is off asks nothing, since trusting it would start nothing.
    package func admitsSession(at root: URL) -> Bool {
        guard sourceKitLSPDiscoveryEnabled(sourceKitLSPLocation(forRoot: root)) else { return false }
        switch trust.decision(for: root) {
            case .trusted:
                return true
            case .declined:
                return false
            case nil:
                trust.requestDecision(for: root)
                return false
        }
    }

    /// The configuration of a sourcekit-lsp session rooted at `root`, a canonical directory; nil when the user does not
    /// trust the repository, when sourcekit-lsp is off for `root`'s project, or when no executable resolves.
    package func configuration(forRoot root: URL) async -> SourceKitLSPService.Configuration? {
        // Checked again although the registry admits every root first: an untrusted root never reaches a server.
        guard trust.isTrusted(root) else { return nil }
        let location = sourceKitLSPLocation(forRoot: root)
        guard sourceKitLSPDiscoveryEnabled(location), let executable = await locate(location) else { return nil }
        return SourceKitLSPService.Configuration(serverExecutable: executable, workspaceRoot: root)
    }

    /// The executable of the SDK tier's scratch session, found from the app-wide location alone; nil when the app-wide
    /// value turns sourcekit-lsp off, or when no executable resolves.
    package func sdkServerExecutable() async -> URL? {
        let location = appWideSourceKitLSPLocation
        guard sourceKitLSPDiscoveryEnabled(location) else { return nil }
        return await locate(location)
    }

    /// The SDK tier's scratch sessions over ``sdkServerExecutable()``, one per platform, in a new private probe
    /// directory; `locateSDK` finds a platform's SDK when its session is first needed. Nil when sourcekit-lsp is off
    /// app-wide or missing, or when the directory cannot be created, which is logged.
    package func resolveSDKTier(
        locateSDK: @escaping @Sendable (SDKPlatform) async -> SDKLocation?
    ) async -> SDKHoverTier.Resolved? {
        guard let executable = await sdkServerExecutable() else { return nil }
        do {
            let probeDirectory = try SDKDocumentationProvider.makeProbeDirectory()
            let provider = SDKDocumentationProvider.scratch(
                serverExecutable: executable, probeDirectory: probeDirectory, locateSDK: locateSDK)
            return SDKHoverTier.Resolved(provider: provider, probeDirectory: probeDirectory)
        } catch {
            PhaseTrace.log("SDK documentation is off: \(error)")
            return nil
        }
    }

    /// The app-wide sourcekit-lsp location. The SDK tier honours only this one: its session belongs to no
    /// repository, so no project's override applies to it.
    package var appWideSourceKitLSPLocation: ToolLocation? {
        location(underKey: ViewerSettings.Key.lspServerLocations)
    }

    /// sourcekit-lsp's location for a session rooted at `root`, as a window on `root`'s project reads it: the
    /// project's override once it holds one, the app-wide value otherwise. `root`'s project is the repository it lies
    /// in (``projectRoot(containing:)``); a root outside every repository has none.
    package func sourceKitLSPLocation(forRoot root: URL) -> ToolLocation? {
        if let project = Self.projectRoot(containing: root) {
            let scopedKey = ViewerSettings.scopedKey(
                ViewerSettings.Key.lspServerLocations, projectKey: ProjectIdentity(root: project).key)
            if defaults.object(forKey: scopedKey) != nil { return location(underKey: scopedKey) }
        }
        return appWideSourceKitLSPLocation
    }

    /// sourcekit-lsp's entry in the `lspServerLocations` value stored under `key`; nil when there is none, which
    /// ``sourceKitLSPDiscoveryEnabled(_:)`` reads as enabled, as ``ViewerSettings`` does.
    private func location(underKey key: String) -> ToolLocation? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try DefaultsJSON.decode([String: ToolLocation].self, from: data)[Self.serverID]
        } catch {
            PhaseTrace.log("unreadable \(key), read as its default: \(error)")
            return nil
        }
    }

    /// The nearest directory at or above `root` that holds a `.git` entry, which is where git finds a work tree's
    /// top level, the root a window adopts as its project; nil when no ancestor holds one.
    /// - Complexity: One `stat(2)` per path component of `root`, at most.
    static func projectRoot(containing root: URL) -> URL? {
        var directory = root.path(percentEncoded: false)
        while true {
            if FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(".git")) {
                return URL(filePath: directory, directoryHint: .isDirectory)
            }
            let parent = (directory as NSString).deletingLastPathComponent
            // `deletingLastPathComponent` returns "/" for "/" and shortens every other path, so the walk ends.
            guard !parent.isEmpty, parent != directory else { return nil }
            directory = parent
        }
    }
}

/// The on-device Apple SDK documentation tier: one scratch sourcekit-lsp session per platform and per app, shared by
/// every window.
@MainActor
package final class SDKHoverTier {
    /// A resolved tier: the provider windows hover through, and the probe directory its sessions run in.
    package struct Resolved: Sendable {
        package let provider: SDKDocumentationProvider
        package let probeDirectory: URL

        package init(provider: SDKDocumentationProvider, probeDirectory: URL) {
            self.provider = provider
            self.probeDirectory = probeDirectory
        }
    }

    private let taskProvider: any TaskProvider
    private let resolve: @Sendable () async -> Resolved?
    /// Stored before its first suspension, so concurrent first callers share one resolution and one scratch session;
    /// a nil outcome is kept too, so the tier is attempted once per app.
    private var resolution: Task<Resolved?, Never>?

    /// - Parameters:
    ///   - taskProvider: Spawns the one resolution.
    ///   - resolve: Resolves the tier; ``LanguageServerPolicy/resolveSDKTier()`` in the app.
    package init(taskProvider: any TaskProvider = .default, resolve: @escaping @Sendable () async -> Resolved?) {
        self.taskProvider = taskProvider
        self.resolve = resolve
    }

    /// The tier's provider, resolved by the first call and shared with every later one; nil when the resolution
    /// found no tier.
    package func provider() async -> SDKDocumentationProvider? {
        if let resolution { return await resolution.value?.provider }
        let resolve = resolve
        let task = taskProvider.task { await resolve() }
        resolution = task
        return await task.value?.provider
    }

    /// Shuts the scratch sessions down and removes their probe directory, once a resolution in flight lands; nothing
    /// happens before the first ``provider()``.
    package func shutdown() async {
        guard let resolved = await resolution?.value else { return }
        await resolved.provider.shutdown()
        do {
            try FileManager.default.removeItem(at: resolved.probeDirectory)
        } catch {
            PhaseTrace.log("the SDK probe directory stays: \(error)")
        }
    }
}
