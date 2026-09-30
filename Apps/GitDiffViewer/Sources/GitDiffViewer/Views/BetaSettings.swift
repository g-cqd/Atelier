import DiffComparison
import DiffTextKit
import Foundation
import SwiftUI

/// The Settings ▸ Beta tab (book D44): work-in-progress features, off by default, with no `#if DEBUG` gate so every
/// user can reach them. Not project-scoped: a beta feature is a developer preference, not a diff-viewing one, so it
/// has no per-project override and its own "Restore Defaults" resets it directly, rather than through
/// ``ViewerSettings/restoreDefaults(_:)``'s per-category diff count.
struct BetaSettings: View {
    /// The text engine a new comparison window starts with (text-renderer.md §4.3): TextKit 2 by default; CoreText
    /// draws rows and decorations only, with no selection, hover or split alignment yet.
    @AppStorage(TextBackendKind.defaultsKey) private var textBackend: TextBackendKind = .textKit2

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(SettingLabel.textEngine, selection: $textBackend) {
                        ForEach(TextBackendKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Text(
                        "Which engine a new comparison window's panes draw with. CoreText is a work in progress: it "
                            + "draws rows and decorations only, with no selection, hover or split alignment yet."
                    )
                    .settingsCaption()
                }
            }
            .formStyle(.grouped)
            BetaSettingsRestoreDefaultsFooter(textBackend: $textBackend)
        }
        .navigationTitle("Beta")
    }
}

/// Resets every beta feature's `@AppStorage` to its default, since these are not `ViewerSettings` properties and so
/// take no part in its per-category "Restore Defaults".
private struct BetaSettingsRestoreDefaultsFooter: View {
    @Binding var textBackend: TextBackendKind

    private var count: Int { textBackend == .textKit2 ? 0 : 1 }

    var body: some View {
        HStack {
            if count > 0 {
                Text("1 setting changed from its default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore Defaults") { textBackend = .textKit2 }
                .disabled(count == 0)
        }
        .padding()
    }
}
