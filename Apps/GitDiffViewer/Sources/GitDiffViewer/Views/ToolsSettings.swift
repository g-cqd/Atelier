import AppKit
import AtelierDiagnostics
import DiffComparison
import DiffRendering
import Foundation
import SwiftUI

/// How a tool or language server's row reads, from its discovered status and its settings.
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

/// The Settings ▸ Tools tab: the diagnostics toggles, then one row per tool and language server whose path
/// controls disclose on demand, and on their own while a pinned path is broken.
struct ToolsSettings: View {
    @Bindable var settings: ViewerSettings
    let scope: SettingsScope
    /// The app's trust decisions, from the environment the app sets on the Settings scene.
    @Environment(RepositoryTrust.self) private var trust: RepositoryTrust?

    /// Where each tool and language server was found, probed for the settings this tab edits.
    @State private var board: ToolStatusBoard
    /// Rows the user expanded or collapsed by hand, overriding the auto-expand-when-broken default.
    @State private var expandedOverrides: [String: Bool] = [:]

    init(settings: ViewerSettings, scope: SettingsScope, discovery: ToolDiscovery) {
        self.settings = settings
        self.scope = scope
        _board = State(initialValue: ToolStatusBoard(discovery: discovery))
    }

    private var statuses: [String: ToolStatus] { board.statuses }

    var body: some View {
        VStack(spacing: 0) {
            SettingsScopeBar(scope: scope)
            Form {
                Section("Diagnostics") {
                    Toggle(SettingLabel.diagnosticsEnabled, isOn: $settings.diagnosticsEnabled)
                    Toggle(SettingLabel.showsHoverDocumentation, isOn: $settings.showsHoverDocumentation)
                    Picker(SettingLabel.hoverPanelMaterial, selection: $settings.hoverPanelMaterial) {
                        ForEach(HoverPanelMaterial.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(!settings.showsHoverDocumentation)
                    Picker(SettingLabel.analyzedSides, selection: $settings.analyzedSides) {
                        ForEach(AnalyzedSides.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(!settings.diagnosticsEnabled)
                    Text(
                        "Each side is analyzed on its own files with its own configuration, and its findings show on "
                            + "its own rows. A side that is a branch, tag or commit is exported to a private "
                            + "temporary folder first, in a repository you trust; in any other, only the working "
                            + "tree is analyzed."
                    )
                    .settingsCaption()
                    Button(SettingLabel.refreshToolStatus) {
                        Task { await board.refreshAll(for: settings, rediscovering: true) }
                    }
                    .disabled(board.isRefreshing)
                    Text(
                        "Enabled tools below run their own discovered executables against this project's files "
                            + "whenever a comparison changes. Refresh looks for them again, after an install."
                    )
                    .settingsCaption()
                }
                Section("Tools") {
                    ForEach(DiagnosticTool.allCases) { tool in
                        toolDisclosure(
                            key: tool.rawValue, title: tool.displayName, executableName: tool.executableName,
                            isEnabled: toolEnabledBinding(tool), customPath: toolCustomPathBinding(tool),
                            footnote: tool.requiredConfigurationFile.map {
                                "Runs only in projects that carry a \($0) file."
                            }
                        )
                    }
                }
                // Usable whatever the other settings (TOOL-02): a tool's path can be set before diagnostics are on,
                // and hover, on by default, runs sourcekit-lsp with diagnostics off.
                Section("Language Servers") {
                    toolDisclosure(
                        key: Self.sourceKitLSPKey, title: "sourcekit-lsp", executableName: "sourcekit-lsp",
                        isEnabled: lspEnabledBinding(Self.sourceKitLSPKey),
                        customPath: lspCustomPathBinding(Self.sourceKitLSPKey),
                        footnote: "Hover documentation runs it, whether or not diagnostics are on."
                    )
                }
                if let trust {
                    TrustedRepositoriesSection(trust: trust)
                }
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, scope: scope, category: .tools)
        }
        .navigationTitle("Tools")
        .task(id: scope.selection) { await board.refreshAll(for: settings, rediscovering: false) }
    }

    private static let sourceKitLSPKey = ToolStatusBoard.sourceKitLSPKey

    /// One tool's row: a summary line, and its path controls in a `DisclosureGroup` that expands on its own while
    /// the pinned path is broken.
    @ViewBuilder
    private func toolDisclosure(
        key: String, title: String, executableName: String, isEnabled: Binding<Bool>, customPath: Binding<String?>,
        footnote: String?
    ) -> some View {
        let row = row(for: key, pinned: customPath.wrappedValue != nil, isEnabled: isEnabled.wrappedValue)
        DisclosureGroup(isExpanded: isExpandedBinding(key: key, autoExpand: row.health == .broken)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(customPath.wrappedValue ?? "Automatic")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Locate…") {
                        if let chosen = chooseExecutable(named: executableName) {
                            customPath.wrappedValue = chosen
                            Task { await board.refresh(key: key, for: settings) }
                        }
                    }
                    if customPath.wrappedValue != nil {
                        Button("Reset") {
                            customPath.wrappedValue = nil
                            Task { await board.refresh(key: key, for: settings) }
                        }
                    }
                }
                if let footnote {
                    Text(footnote).settingsCaption()
                }
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(row.color).frame(width: 8, height: 8)
                Text(title)
                Text(
                    isEnabled.wrappedValue
                        ? toolStatusDescription(statuses[key], pinned: customPath.wrappedValue != nil) : "Off"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer()
                Toggle("Enable \(title)", isOn: isEnabled)
                    .labelsHidden()
            }
        }
    }

    private func isExpandedBinding(key: String, autoExpand: Bool) -> Binding<Bool> {
        Binding(
            get: { expandedOverrides[key] ?? autoExpand },
            set: { expandedOverrides[key] = $0 }
        )
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

    private func chooseExecutable(named name: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the \(name) executable"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
