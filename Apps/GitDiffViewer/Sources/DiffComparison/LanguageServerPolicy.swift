package import AtelierDiagnostics
package import AtelierLSP
import DiffGit
package import Foundation

/// Decides whether and how GitDiffViewer launches sourcekit-lsp: per repository root for the language-server tier,
/// and app-wide for the SDK tier, whose scratch session has no root.
@MainActor
package final class LanguageServerPolicy {
    /// Finds sourcekit-lsp's executable for a persisted location, honoring its custom path; nil when none resolves.
    package typealias Locate = @Sendable (ToolLocation?) async -> URL?

    /// The id sourcekit-lsp's location is stored under in ``ViewerSettings/lspServerLocations``.
    static let serverID = "sourcekit-lsp"

    private let defaults: UserDefaults
    private let locate: Locate

    /// - Parameters:
    ///   - defaults: Where ``ViewerSettings`` persists `lspServerLocations`, app-wide and per project.
    ///   - locate: Finds the executable; ``locate(with:)`` in the app.
    package init(defaults: UserDefaults = .standard, locate: @escaping Locate) {
        self.defaults = defaults
        self.locate = locate
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

    /// The configuration of a sourcekit-lsp session rooted at `root`, a canonical directory; nil when sourcekit-lsp is
    /// off for `root`'s project, or when no executable resolves.
    package func configuration(forRoot root: URL) async -> SourceKitLSPService.Configuration? {
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
