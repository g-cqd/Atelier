import AtelierDiagnostics
import DiffComparison
import SwiftUI

/// Toolbar item: a button showing the warning and error totals that opens every finding of the comparison,
/// grouped by file.
struct FindingsNavigatorButton: View {
    let model: DiffViewerModel
    @State private var isPresented = false

    var body: some View {
        if model.settings.diagnosticsEnabled, let diagnostics = model.diagnostics, !diagnostics.summary.isEmpty {
            Button {
                isPresented.toggle()
            } label: {
                let summary = diagnostics.summary
                HStack(spacing: 6) {
                    if summary.warnings > 0 {
                        Label("\(summary.warnings)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if summary.errors > 0 {
                        Label("\(summary.errors)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.callout.monospacedDigit())
            }
            .buttonStyle(.plain)
            .toolbarItemMetrics()
            .accessibilityLabel("Findings")
            .help("Every warning and error found in the comparison")
            .popover(isPresented: $isPresented) {
                FindingsNavigatorPopover(model: model, isPresented: $isPresented)
            }
        }
    }
}

/// The popover's own content: one section per file, its findings underneath, each row navigable.
private struct FindingsNavigatorPopover: View {
    let model: DiffViewerModel
    @Binding var isPresented: Bool

    private var groups: [FindingsNavigatorGrouping.FileGroup] {
        FindingsNavigatorGrouping.groups(model.diagnostics?.findingsByFile ?? [:])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.path) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text((group.path as NSString).lastPathComponent)
                            .font(.headline)
                            .help(group.path)
                        ForEach(Array(group.findings.enumerated()), id: \.offset) { _, finding in
                            FindingRow(finding: finding) {
                                // Opens the file, then its line once the file's render lands.
                                model.reveal(finding)
                                isPresented = false
                            }
                        }
                    }
                    if group.path != groups.last?.path { Divider() }
                }
                if groups.isEmpty {
                    Text("No findings").foregroundStyle(.secondary).padding()
                }
            }
            .padding(12)
        }
        .frame(minWidth: 340, idealWidth: 420, maxWidth: 480, minHeight: 120, maxHeight: 420)
    }
}

private struct FindingRow: View {
    let finding: Finding
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: finding.severity.systemImage)
                    .foregroundStyle(finding.severity.color)
                    .frame(width: 14, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.ruleID)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(finding.tool.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(finding.message)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(finding.message) — line \(finding.line)")
    }
}

extension Finding.Severity {
    fileprivate var systemImage: String {
        switch self {
            case .note: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
        }
    }

    fileprivate var color: Color {
        switch self {
            case .note: .secondary
            case .warning: .orange
            case .error: .red
        }
    }
}
