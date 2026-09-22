import AppKit
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
    /// Kept alive for as long as it is on screen: `NSPopover.show` does not itself retain the popover past this
    /// scope, and it is transient (dismisses on an outside click) so there is never more than one at a time.
    @State private var diagnosticPopover: NSPopover?
    /// Bumped by every ``recompute()``; a mapping that lands after a newer one started is dropped.
    @State private var recomputeGeneration = 0

    var body: some View {
        DiffTextView(
            rendered: rendered, gutter: gutter, keepsScrollPosition: keepsScrollPosition, wrapsLines: wrapsLines,
            wrapColumn: wrapColumn, showsMinimap: showsMinimap, syncsScrolling: syncsScrolling,
            scrollRequest: scrollRequest, splitController: splitController, onGapDrag: onGapDrag,
            currentExpansion: currentExpansion, onDisplayed: onDisplayed,
            hoverEnabled: model.settings.showsHoverDocumentation && model.hoverDocs != nil,
            hoverResolver: hoverResolver,
            diagnosticOverlay: model.settings.diagnosticsEnabled ? overlay : nil, diagnosticsVersion: version,
            onDiagnosticClick: showDiagnosticPopover
        )
        .onAppear { recompute() }
        .onChange(of: rendered.id) { recompute() }
        .onChange(of: model.diagnosticsVersion) { recompute() }
        .onChange(of: model.settings.diagnosticsEnabled) { recompute() }
        .onChange(of: model.settings.analyzedSides) { recompute() }
    }

    /// Maps this pane's findings off the main actor and applies the result, guarded by generation so a slower,
    /// superseded mapping (an older render, or diagnostics that have since moved on) can never overwrite a newer
    /// one that already landed.
    private func recompute() {
        recomputeGeneration &+= 1
        let generation = recomputeGeneration
        guard model.settings.diagnosticsEnabled, let diagnostics = model.diagnostics else {
            overlay.replace([:])
            version += 1
            return
        }
        let paths = model.diagnosticFilePaths
        let findings = diagnostics.findingsByFile
        let includesOldSide = model.settings.analyzedSides == .both
        let rendered = rendered
        Task {
            let rows = await DiagnosticRowMapper.rowsOffMain(
                for: rendered, paths: paths, findings: findings, includesOldSide: includesOldSide)
            guard generation == recomputeGeneration else { return }
            overlay.replace(rows)
            version += 1
        }
    }

    /// Resolves a hover hit through ``DiffComparison/HoverDocumentationModel`` and structures and colors its
    /// markdown for the panel, using this pane's own palette; nil while no hover documentation model is attached,
    /// so ``DiffTextView`` never asks. When the hovered row also carries diagnostics, they join the same document
    /// (``HoverDocument/diagnostics``), so the unified panel shows the issue the squiggle pointed at alongside
    /// whatever documentation resolved for the identifier under it -- one hover, one surface.
    private var hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? {
        guard let hoverDocs = model.hoverDocs else { return nil }
        let palette = rendered.palette
        let overlay = overlay
        return { hit in
            let side: HoverQuerySide = hit.side == .new ? .new : .old
            let rowDiagnostics = overlay.row(hit.row)?.findings.map { HoverDocument.DiagnosticEntry($0) } ?? []
            guard
                let content = await hoverDocs.hover(
                    fileIndex: hit.fileIndex, side: side, line: hit.line, utf16Column: hit.utf16Column)
            else {
                guard !rowDiagnostics.isEmpty else { return nil }
                return HoverDocument(diagnostics: rowDiagnostics)
            }
            var document = HoverDocument.build(from: content, palette: palette)
            guard !rowDiagnostics.isEmpty else { return document }
            document = HoverDocument(
                declaration: document.declaration, summary: document.summary, discussion: document.discussion,
                parameters: document.parameters, returns: document.returns, provenance: document.provenance,
                extraCandidates: document.extraCandidates, diagnostics: rowDiagnostics)
            return document
        }
    }

    /// Presents ``DiagnosticFindingsList`` as an `NSPopover` anchored on the row's own frame, the same way Xcode's
    /// issue navigator opens off a line -- the fix for the popover that used to anchor to the whole pane
    /// (SwiftUI's `.popover(item:)` has no notion of "this row", only "this view"), which put it at the pane's own
    /// origin instead of next to whatever was clicked.
    private func showDiagnosticPopover(rowIndex: Int, findings: [Finding], anchorRect: NSRect, in view: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: DiagnosticFindingsList(findings: findings))
        diagnosticPopover = popover
        popover.show(relativeTo: anchorRect, of: view, preferredEdge: .minY)
    }
}

extension HoverDocument.DiagnosticEntry {
    fileprivate nonisolated init(_ finding: Finding) {
        self.init(
            severity: .init(finding.severity), message: "\(finding.ruleID): \(finding.message)",
            tool: finding.tool.displayName)
    }
}

extension HoverDocument.DiagnosticEntry.Severity {
    fileprivate nonisolated init(_ severity: Finding.Severity) {
        switch severity {
            case .error: self = .error
            case .warning: self = .warning
            case .note: self = .note
        }
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
