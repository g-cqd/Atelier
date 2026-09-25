package import AtelierDiagnostics
package import AtelierLSP
import AtelierSyntaxModel
import Foundation
import Observation

/// The Tools tab's statuses: where each diagnostics tool and language server was found, and its version, probed
/// through ``ToolDiscovery`` for the settings the tab edits. The view reads it and binds each row's controls to
/// ``ViewerSettings``.
@Observable
@MainActor
package final class ToolStatusBoard {
    /// The id sourcekit-lsp's row and location are kept under.
    package static let sourceKitLSPKey = LanguageServerDescriptor.sourceKitLSP.id
    /// The language servers with a row, each kept under its id.
    package static let languageServers = LanguageServerDescriptor.all

    /// By ``DiagnosticTool/rawValue`` for a tool, by server id for a language server; absent until probed.
    package private(set) var statuses: [String: ToolStatus] = [:]
    package private(set) var isRefreshing = false

    private let discovery: ToolDiscovery
    /// Bumped by every ``refreshAll(for:rediscovering:)``: a refresh another has replaced, when the tab changes scope
    /// mid-way, writes nothing more, so the rows never show the previous scope's statuses.
    @ObservationIgnored private var generation = 0

    /// What a language server's row says it does: the languages whose hovers it answers, and the runtime it needs.
    package static func footnote(for server: LanguageServerDescriptor) -> String {
        let languages = server.languages.map(languageName).sorted().formatted(.list(type: .and))
        let runtime = server.runtimeExecutableName.map { " It runs on \($0), found the same way." } ?? ""
        return "Hover documentation runs it for \(languages), whether or not diagnostics are on.\(runtime)"
    }

    private static func languageName(_ language: Language) -> String {
        switch language {
            case .swift: "Swift"
            case .typescript: "TypeScript"
            case .javascript: "JavaScript"
            case .go: "Go"
            default: language.name
        }
    }

    package init(discovery: ToolDiscovery) {
        self.discovery = discovery
    }

    /// Probes every row for `settings`, as the tab does when it appears or changes scope. The Refresh button passes
    /// `rediscovering`, which first drops discovery's caches, `xcrun`'s answers, the login shell's `PATH` and the
    /// versions, so a tool installed since the last probe is found without relaunching the app (TOOL-01).
    package func refreshAll(for settings: ViewerSettings, rediscovering: Bool) async {
        generation &+= 1
        let generation = generation
        isRefreshing = true
        if rediscovering { await discovery.invalidate() }
        for key in DiagnosticTool.allCases.map(\.rawValue) + Self.languageServers.map(\.id) {
            guard generation == self.generation else { return }
            await refresh(key: key, for: settings, generation: generation)
        }
        guard generation == self.generation else { return }
        isRefreshing = false
    }

    /// Probes the row under `key` for `settings`: a tool through its own location, a language server the way the
    /// language server policy finds it. A disabled language server has no status.
    package func refresh(key: String, for settings: ViewerSettings) async {
        await refresh(key: key, for: settings, generation: generation)
    }

    /// Probes the row under `key`, writing the answer only while no newer refresh has started.
    private func refresh(key: String, for settings: ViewerSettings, generation: Int) async {
        let status = await status(ofRow: key, for: settings)
        guard generation == self.generation else { return }
        statuses[key] = status
    }

    private func status(ofRow key: String, for settings: ViewerSettings) async -> ToolStatus? {
        if let tool = DiagnosticTool(rawValue: key) {
            return await discovery.status(tool, location: settings.toolLocations[tool])
        }
        guard let server = Self.languageServers.first(where: { $0.id == key }) else { return nil }
        let location = settings.lspServerLocations[key]
        if let location, !location.isEnabled { return nil }
        // The rungs ``LanguageServerDescriptor/executableQuery(customPath:overridePrefix:)`` gives the policy, with
        // the rung that answered, which the row names.
        var located: (url: URL, origin: ToolOrigin)?
        for name in server.executableNames {
            located = await discovery.locate(
                executableName: name, overrideVariable: "GDV_" + server.environmentName,
                customPath: location?.customPath, searchesToolchain: server.searchesToolchain,
                homeRelativeDirectories: server.homeRelativeDirectories)
            if located != nil { break }
        }
        // No version: a language server reports one only once launched, as its own initialize answer.
        return ToolStatus(tool: .swiftlint, url: located?.url, origin: located?.origin, version: nil)
    }
}
