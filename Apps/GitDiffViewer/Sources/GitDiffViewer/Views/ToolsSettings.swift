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

/// The Settings ▸ Tools tab (R1): the diagnostics master toggles up top, then one list with a single summary row
/// per tool — status dot, name, status text, an enable toggle — each disclosing its path row (Locate…/Reset) on
/// demand rather than showing it always. A pinned path that is not usable auto-expands so the problem is visible
/// without a click. The whole list dims while the master toggle is off, since none of it can run anyway.
struct ToolsSettings: View {
    @Bindable var settings: ViewerSettings
    let discovery: ToolDiscovery

    /// Keyed by ``DiagnosticTool/rawValue`` for a static-analysis tool, or the server id for a language server.
    @State private var statuses: [String: ToolStatus] = [:]
    @State private var isRefreshing = false
    /// Rows the user expanded or collapsed by hand, overriding the auto-expand-when-broken default.
    @State private var expandedOverrides: [String: Bool] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Diagnostics") {
                    Toggle(SettingLabel.diagnosticsEnabled, isOn: $settings.diagnosticsEnabled)
                    Toggle(SettingLabel.showsHoverDocumentation, isOn: $settings.showsHoverDocumentation)
                    Picker(SettingLabel.analyzedSides, selection: $settings.analyzedSides) {
                        Text("Newer side").tag(AnalyzedSides.newer)
                        Text("Both sides").tag(AnalyzedSides.both)
                    }
                    .disabled(!settings.diagnosticsEnabled)
                    Text(
                        "Findings on a removed or old line only show with \"Both sides\", and are a best-effort "
                            + "echo of the newer side's analysis at the same line number, not an independent look "
                            + "at the old content."
                    )
                    .settingsCaption()
                    Button(SettingLabel.refreshToolStatus) { Task { await refreshAll() } }
                        .disabled(isRefreshing)
                    // R6: friction on a trust-sensitive setting — shown always, not only on first enable, since
                    // that reads the same and costs nothing extra to keep visible.
                    Text(
                        "Enabled tools below run their own discovered executables against this project's files "
                            + "whenever a comparison changes."
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
                .disabled(!settings.diagnosticsEnabled)
                .opacity(settings.diagnosticsEnabled ? 1 : 0.5)
                Section("Language Servers") {
                    toolDisclosure(
                        key: Self.sourceKitLSPKey, title: "sourcekit-lsp", executableName: "sourcekit-lsp",
                        isEnabled: lspEnabledBinding(Self.sourceKitLSPKey),
                        customPath: lspCustomPathBinding(Self.sourceKitLSPKey), footnote: nil
                    )
                }
                .disabled(!settings.diagnosticsEnabled)
                .opacity(settings.diagnosticsEnabled ? 1 : 0.5)
            }
            .formStyle(.grouped)
            SettingsRestoreDefaultsFooter(settings: settings, category: .tools)
        }
        .navigationTitle("Tools")
        .task { await refreshAll() }
    }

    private static let sourceKitLSPKey = "sourcekit-lsp"

    /// One tool's row: a summary line (dot, name, status, enable toggle) always shown, and a `DisclosureGroup`
    /// revealing the path row — the rare-use control (P5) — only when expanded, auto-expanded when the pinned
    /// path is broken so the problem does not hide behind a click.
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
