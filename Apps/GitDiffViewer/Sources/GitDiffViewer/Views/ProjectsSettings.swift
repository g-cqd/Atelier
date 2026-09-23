import DiffComparison
import Foundation
import SwiftUI

/// Settings ▸ Projects: every project the app knows of, what each overrides and its default, a button per override
/// that drops it, and the project's own Edit, Reset All and Remove buttons.
struct ProjectsSettings: View {
    let scope: SettingsScope

    var body: some View {
        Form {
            Section {
                if scope.entries.isEmpty {
                    Text("No project yet. A repository opened in a comparison window appears here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(scope.entries) { entry in
                    ProjectRow(entry: entry, scope: scope)
                }
            } header: {
                Text("Projects")
            } footer: {
                Text(
                    "A project uses the default settings until you change one for it, here with the selector at "
                        + "the top of each tab, or in its comparison window."
                )
                .settingsCaption()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Projects")
    }
}

/// One project: its name and how many settings it overrides, disclosing each override with its default and a Reset
/// button, then the project's own buttons.
private struct ProjectRow: View {
    let entry: SettingsScope.Entry
    let scope: SettingsScope

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entry.overrides) { override in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(override.label)
                            Text("\(override.value) — default: \(override.defaultValue)")
                                .settingsCaption()
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Reset") { scope.resetOverride(override.key, of: entry.project) }
                    }
                }
                HStack {
                    Button("Edit Settings") {
                        scope.select(.project(entry.project))
                        scope.appSettings.settingsPane = .general
                    }
                    Button("Reset All") { scope.resetOverrides(of: entry.project) }
                        .disabled(entry.overrides.isEmpty)
                    Spacer()
                    Button("Remove", role: .destructive) { scope.remove(entry.project) }
                        .help("Drop this project's own settings and remove it from the list until it is opened again")
                }
                .padding(.top, 2)
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text(entry.project.name)
                    .help(entry.project.displayPath)
                Spacer()
                Text(
                    entry.overrides.isEmpty
                        ? "Uses the defaults"
                        : "\(entry.overrides.count) setting\(entry.overrides.count == 1 ? "" : "s") of its own"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
