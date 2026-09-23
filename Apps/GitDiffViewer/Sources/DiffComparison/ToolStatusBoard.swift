package import AtelierDiagnostics
import Foundation
import Observation

/// The Tools tab's statuses: where each diagnostics tool and language server was found, and its version, probed
/// through ``ToolDiscovery`` for the settings the tab edits. The view reads it and binds each row's controls to
/// ``ViewerSettings``.
@Observable
@MainActor
package final class ToolStatusBoard {
    /// The id sourcekit-lsp's row and location are kept under.
    package static let sourceKitLSPKey = "sourcekit-lsp"

    /// By ``DiagnosticTool/rawValue`` for a tool, by server id for a language server; absent until probed.
    package private(set) var statuses: [String: ToolStatus] = [:]
    package private(set) var isRefreshing = false

    private let discovery: ToolDiscovery

    package init(discovery: ToolDiscovery) {
        self.discovery = discovery
    }

    /// Probes every row for `settings`, as the tab does when it appears or changes scope. The Refresh button passes
    /// `rediscovering`, which first drops discovery's caches, `xcrun`'s answers, the login shell's `PATH` and the
    /// versions, so a tool installed since the last probe is found without relaunching the app (TOOL-01).
    package func refreshAll(for settings: ViewerSettings, rediscovering: Bool) async {
        isRefreshing = true
        if rediscovering { await discovery.invalidate() }
        for tool in DiagnosticTool.allCases {
            await refresh(key: tool.rawValue, for: settings)
        }
        await refresh(key: Self.sourceKitLSPKey, for: settings)
        isRefreshing = false
    }

    /// Probes the row under `key` for `settings`: a tool through its own location, sourcekit-lsp the way the language
    /// server policy finds it. A disabled language server has no status.
    package func refresh(key: String, for settings: ViewerSettings) async {
        if let tool = DiagnosticTool(rawValue: key) {
            statuses[key] = await discovery.status(tool, location: settings.toolLocations[tool])
            return
        }
        guard key == Self.sourceKitLSPKey else { return }
        let location = settings.lspServerLocations[key]
        if let location, !location.isEnabled {
            statuses[key] = nil
            return
        }
        let located = await discovery.locate(
            executableName: Self.sourceKitLSPKey, overrideVariable: "GDV_SOURCEKIT_LSP",
            customPath: location?.customPath, searchesToolchain: true)
        // No version: sourcekit-lsp can only report one by launching the language server itself.
        statuses[key] = ToolStatus(tool: .swiftlint, url: located?.url, origin: located?.origin, version: nil)
    }
}
