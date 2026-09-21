import AppKit
import AtelierDiagnostics
import DiffComparison
import Foundation
import SwiftUI

/// A tool or server's discovered status, keyed the same way as ``ToolsSettings/statuses``: a
/// ``DiagnosticTool/rawValue`` or a language-server id such as `"sourcekit-lsp"`.
private enum ToolStatusRow {
    case available
    case missing
    /// A custom path was set but does not point at an executable file.
    case pinnedBroken
    case disabled
}

/// How a status row's dot should read at a glance: green when a healthy tool was found, red when nothing was
/// found, orange when a pinned path was set but is not usable, gray when the tool is deliberately off.
private enum ToolStatusHealth {
    case available
    case missing
    case broken
    case off
}

extension ToolStatusRow {
    fileprivate var health: ToolStatusHealth {
        switch self {
            case .available: .available
            case .missing: .missing
            case .pinnedBroken: .broken
            case .disabled: .off
        }
    }

    fileprivate var color: Color {
        switch health {
            case .available: .green
            case .missing: .red
            case .broken: .orange
            case .off: .gray
        }
    }
}

/// The Settings ▸ Tools tab: the diagnostics master toggles, then one section per static-analysis tool and one for
/// the language servers diagnostics and hover documentation share, each showing where the tool was found (or why
/// it was not) and letting the user pin a custom executable.
struct ToolsSettings: View {
    @Bindable var settings: ViewerSettings
    let discovery: ToolDiscovery

    /// Keyed by ``DiagnosticTool/rawValue`` for a static-analysis tool, or the server id for a language server.
    @State private var statuses: [String: ToolStatus] = [:]
    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section("Diagnostics") {
                Toggle("Analyze changed Swift files", isOn: $settings.diagnosticsEnabled)
                Text(
                    "Runs the enabled tools below on the files of a comparison; results appear inline and in the status bar."
                )
                .settingsCaption()
                Toggle("Show documentation on hover", isOn: $settings.showsHoverDocumentation)
                Text("Shows a language server's documentation for the symbol under the pointer.")
                    .settingsCaption()
                Button("Refresh Tool Status") { Task { await refreshAll() } }
                    .disabled(isRefreshing)
            }
            ForEach(DiagnosticTool.allCases) { tool in
                Section(tool.displayName) {
                    toolRow(
                        title: "Enabled", key: tool.rawValue,
                        isEnabled: toolEnabledBinding(tool),
                        customPath: toolCustomPathBinding(tool),
                        executableName: tool.executableName
                    )
                    if let requiredConfigurationFile = tool.requiredConfigurationFile {
                        Text("Runs only in projects that carry a \(requiredConfigurationFile) file.")
                            .settingsCaption()
                    }
                }
            }
            Section("Language Servers") {
                toolRow(
                    title: "sourcekit-lsp", key: Self.sourceKitLSPKey,
                    isEnabled: lspEnabledBinding(Self.sourceKitLSPKey),
                    customPath: lspCustomPathBinding(Self.sourceKitLSPKey),
                    executableName: "sourcekit-lsp"
                )
            }
        }
        .formStyle(.grouped)
        .task { await refreshAll() }
    }

    private static let sourceKitLSPKey = "sourcekit-lsp"

    @ViewBuilder
    private func toolRow(
        title: String, key: String, isEnabled: Binding<Bool>, customPath: Binding<String?>, executableName: String
    ) -> some View {
        Toggle("Enable \(title)", isOn: isEnabled)
        HStack(spacing: 6) {
            let row = row(for: key, pinned: customPath.wrappedValue != nil, isEnabled: isEnabled.wrappedValue)
            Circle()
                .fill(row.color)
                .frame(width: 8, height: 8)
            Text(
                isEnabled.wrappedValue
                    ? toolStatusDescription(statuses[key], pinned: customPath.wrappedValue != nil) : "Off"
            )
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        HStack {
            Text(customPath.wrappedValue ?? "Automatic")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Locate…") {
                if let chosen = chooseExecutable(named: executableName) {
                    customPath.wrappedValue = chosen
                    Task { await refresh(key: key) }
                }
            }
            if customPath.wrappedValue != nil {
                Button("Reset") {
                    customPath.wrappedValue = nil
                    Task { await refresh(key: key) }
                }
            }
        }
    }

    private func row(for key: String, pinned: Bool, isEnabled: Bool) -> ToolStatusRow {
        guard isEnabled else { return .disabled }
        guard let status = statuses[key] else { return .missing }
        if status.isAvailable { return .available }
        return pinned ? .pinnedBroken : .missing
    }

    // MARK: - Bindings

    private func toolEnabledBinding(_ tool: DiagnosticTool) -> Binding<Bool> {
        Binding(
            get: { settings.toolLocations[tool]?.isEnabled ?? true },
            set: { newValue in
                var location = settings.toolLocations[tool] ?? ToolLocation()
                location.isEnabled = newValue
                settings.toolLocations[tool] = location
            }
        )
    }

    private func toolCustomPathBinding(_ tool: DiagnosticTool) -> Binding<String?> {
        Binding(
            get: { settings.toolLocations[tool]?.customPath },
            set: { newValue in
                var location = settings.toolLocations[tool] ?? ToolLocation()
                location.customPath = newValue
                settings.toolLocations[tool] = location
            }
        )
    }

    private func lspEnabledBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { settings.lspServerLocations[key]?.isEnabled ?? true },
            set: { newValue in
                var location = settings.lspServerLocations[key] ?? ToolLocation()
                location.isEnabled = newValue
                settings.lspServerLocations[key] = location
            }
        )
    }

    private func lspCustomPathBinding(_ key: String) -> Binding<String?> {
        Binding(
            get: { settings.lspServerLocations[key]?.customPath },
            set: { newValue in
                var location = settings.lspServerLocations[key] ?? ToolLocation()
                location.customPath = newValue
                settings.lspServerLocations[key] = location
            }
        )
    }

    // MARK: - Status loading

    private func refreshAll() async {
        isRefreshing = true
        for tool in DiagnosticTool.allCases {
            await refresh(key: tool.rawValue)
        }
        await refresh(key: Self.sourceKitLSPKey)
        isRefreshing = false
    }

    private func refresh(key: String) async {
        if let tool = DiagnosticTool(rawValue: key) {
            let location = settings.toolLocations[tool]
            statuses[key] = await discovery.status(tool, location: location)
            return
        }
        guard key == Self.sourceKitLSPKey else { return }
        let location = settings.lspServerLocations[key]
        if let location, !location.isEnabled {
            statuses[key] = nil
            return
        }
        if let located = await discovery.locate(
            executableName: "sourcekit-lsp", overrideVariable: "GDV_SOURCEKIT_LSP",
            customPath: location?.customPath, searchesToolchain: true
        ) {
            // sourcekit-lsp has no lightweight, side-effect-free way to report its own version, so its status shows
            // only where it was found; probing it the way ``ToolDiscovery`` probes a diagnostic tool would mean
            // launching the language server itself just to read a banner.
            statuses[key] = ToolStatus(tool: .swiftlint, url: located.url, origin: located.origin, version: nil)
        } else {
            statuses[key] = ToolStatus(tool: .swiftlint, url: nil, origin: nil, version: nil)
        }
    }

    private func chooseExecutable(named name: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \(name) executable"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
