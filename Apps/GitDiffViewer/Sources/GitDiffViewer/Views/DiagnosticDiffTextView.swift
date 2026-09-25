import AppKit
import AtelierDiagnostics
import DiffComparison
import DiffCore
import DiffRendering
import DiffTextKit
import SwiftUI

/// ``DiffTextView`` plus the diagnostics of its own rendered text: squiggles, tinted gutter line numbers, and the
/// findings popover a click on one opens, all kept in the pane's own ``PaneDiagnostics``.
struct DiagnosticDiffTextView: View {
    let model: DiffViewerModel
    let rendered: RenderedText
    let gutter: GutterStyle
    var keepsScrollPosition = false
    var wrapsLines = true
    var wrapColumn = 0
    var showsMinimap = true
    var syncsScrolling = true
    var scrollRequest: ScrollRequest?
    var splitController: SplitPaneController?
    var onGapDrag: ((GapDragEvent) -> Void)?
    /// Called once the pane shows a new render, its first included.
    var onDisplayed: (() -> Void)?
    /// The file shown, whose scroll position the pane keeps in the model's ``DiffViewerModel/scrollMemory`` while its
    /// tab is open; nil keeps none.
    var scrollMemoryPath: String?
    /// The height of bars above the pane that AppKit does not know of, the tab bar, which it runs beneath (TAB-09).
    var underBars: CGFloat = 0

    /// This pane's findings, since its rows are its own.
    @State private var diagnostics = PaneDiagnostics()

    var body: some View {
        DiffTextView(
            rendered: rendered, gutter: gutter, keepsScrollPosition: keepsScrollPosition, wrapsLines: wrapsLines,
            wrapColumn: wrapColumn, showsMinimap: showsMinimap, syncsScrolling: syncsScrolling,
            scrollRequest: scrollRequest, splitController: splitController, onGapDrag: onGapDrag,
            onChangeToggle: { model.toggleChange($0) }, onDisplayed: onDisplayed,
            hoverEnabled: model.settings.showsHoverDocumentation && model.hoverDocs != nil,
            hoverResolver: diagnostics.hoverResolver(docs: model.hoverDocs, palette: rendered.palette),
            hoverPanelMaterial: model.settings.hoverPanelMaterial,
            diagnosticOverlay: model.settings.diagnosticsEnabled ? diagnostics.overlay : nil,
            diagnosticsVersion: diagnostics.version,
            onDiagnosticClick: diagnostics.showFindings,
            scrollMemory: model.scrollMemory, scrollMemoryPath: scrollMemoryPath,
            scrollsPastEnd: model.settings.scrollsPastEnd, bouncesAtEdges: model.settings.bouncesAtEdges,
            underBars: underBars
        )
        .decorated(with: model.decorations(for: rendered), viewport: model.decorationViewport)
        .followingDiagnostics(of: rendered, in: model, into: diagnostics)
    }
}

extension View {
    /// Maps `model`'s findings to `rendered`'s rows into `diagnostics` as the pane appears, and again whenever the text,
    /// the findings, or the diagnostics settings change.
    func followingDiagnostics(of rendered: RenderedText, in model: DiffViewerModel, into diagnostics: PaneDiagnostics)
        -> some View
    {
        let recompute = { diagnostics.recompute(for: rendered, model: model) }
        return onAppear(perform: recompute)
            .onChange(of: rendered.id, recompute)
            .onChange(of: model.diagnosticsVersion, recompute)
            .onChange(of: model.settings.diagnosticsEnabled, recompute)
            .onChange(of: model.settings.analyzedSides, recompute)
    }
}

/// The findings on one row, native and simple: an icon for how serious each is, its rule and message, which tool
/// reported it, and any other location it points to.
struct DiagnosticFindingsList: View {
    let findings: [Finding]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: finding.severity.systemImage)
                            .foregroundStyle(finding.severity.color)
                            .frame(width: 14, alignment: .center)
                        Text(finding.ruleID)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(finding.tool.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(finding.message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(finding.related.enumerated()), id: \.offset) { _, related in
                        Text(
                            "\((related.file as NSString).lastPathComponent):\(related.line)"
                                + (related.message.map { " — \($0)" } ?? "")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if index < findings.count - 1 { Divider() }
            }
        }
        .padding(12)
        .frame(minWidth: 260, maxWidth: 420)
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
