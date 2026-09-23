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
            return try JSONDecoder().decode([String: ToolLocation].self, from: data)[Self.serverID]
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
