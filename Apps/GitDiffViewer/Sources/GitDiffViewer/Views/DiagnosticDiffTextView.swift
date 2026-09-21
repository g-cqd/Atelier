import AtelierDiagnostics
import DiffComparison
import DiffCore
import DiffRendering
import DiffTextKit
import SwiftUI

/// ``DiffTextView`` plus the diagnostics squiggles and gutter badges for its own rendered text, and the popover a
/// badge click opens. Kept apart from ``DiffTextView`` itself, which knows nothing of the model or the settings
/// that gate diagnostics.
///
/// One instance owns one ``DiagnosticOverlay``: `unified`, `old` and `new` each lay their rows out on their own, so
/// each needs its own row-to-finding mapping even though they all show the same file.
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
    var onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)?
    var currentExpansion: ((GapKey) -> GapExpansion)?
    var onDisplayed: (() -> Void)?

    @State private var overlay = DiagnosticOverlay()
    @State private var version = 0
    @State private var clicked: ClickedDiagnostics?

    var body: some View {
        DiffTextView(
            rendered: rendered, gutter: gutter, keepsScrollPosition: keepsScrollPosition, wrapsLines: wrapsLines,
            wrapColumn: wrapColumn, showsMinimap: showsMinimap, syncsScrolling: syncsScrolling,
            scrollRequest: scrollRequest, splitController: splitController, onGapDrag: onGapDrag,
            currentExpansion: currentExpansion, onDisplayed: onDisplayed,
            hoverEnabled: model.settings.showsHoverDocumentation && model.hoverDocs != nil && !model.isRendering,
            hoverResolver: hoverResolver,
            diagnosticOverlay: model.settings.diagnosticsEnabled ? overlay : nil, diagnosticsVersion: version,
            onDiagnosticClick: { _, findings, _ in clicked = ClickedDiagnostics(findings: findings) }
        )
        // The badge's own rect is in the gutter's AppKit (bottom-left origin) coordinates, which do not map
        // cleanly onto SwiftUI's anchor space; anchoring to the pane itself keeps this simple and still puts the
        // popover right next to the row that was clicked.
        .popover(item: $clicked) { clicked in
            DiagnosticFindingsList(findings: clicked.findings)
        }
        .onAppear { recompute() }
        .onChange(of: rendered.id) { recompute() }
        .onChange(of: model.diagnosticsVersion) { recompute() }
        .onChange(of: model.settings.diagnosticsEnabled) { recompute() }
    }

    private func recompute() {
        guard model.settings.diagnosticsEnabled, let diagnostics = model.diagnostics else {
            overlay.replace([:])
            version += 1
            return
        }
        let rows = DiagnosticRowMapper.rows(
            for: rendered, paths: model.diagnosticFilePaths, findings: diagnostics.findingsByFile)
        overlay.replace(rows)
        version += 1
    }

    /// Resolves a hover hit through ``DiffComparison/HoverDocumentationModel`` and renders its markdown for the
    /// popover; nil while no hover documentation model is attached, so ``DiffTextView`` never asks.
    private var hoverResolver: (@Sendable (HoverHit) async -> AttributedString?)? {
        guard let hoverDocs = model.hoverDocs else { return nil }
        return { hit in
            let side: HoverQuerySide = hit.side == .new ? .new : .old
            guard
                let content = await hoverDocs.hover(
                    fileIndex: hit.fileIndex, side: side, line: hit.line, utf16Column: hit.utf16Column)
            else { return nil }
            return renderHoverMarkdown(content.markdown)
        }
    }
}

private struct ClickedDiagnostics: Identifiable {
    let id = UUID()
    let findings: [Finding]
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
