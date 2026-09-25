import AemiCore
import AppKit
import AtelierDiagnostics
import DiffComparison
import DiffRendering
import DiffTextKit
import Observation
import SwiftUI

/// The findings one code pane shows on its rows, for the single-file view and the card list alike (book DIAG-03):
/// mapped to the pane's rows off the main actor, kept in an overlay the pane draws, joined to the hover under the
/// pointer, and opened in a popover from a decorated line number.
@Observable
final class PaneDiagnostics {
    /// The pane's rows and their findings; replaced whole by each mapping.
    @ObservationIgnored let overlay = DiagnosticOverlay()
    /// Bumped each time ``overlay`` changes, which the pane cannot see of a reference.
    private(set) var version = 0
    /// Bumped by every ``recompute(for:model:)``; a mapping that lands after a newer one started is dropped.
    @ObservationIgnored private var generation = 0
    /// Retains the transient findings popover, which `NSPopover.show` does not.
    @ObservationIgnored private var popover: NSPopover?

    /// Maps `model`'s findings to the rows of `rendered` off the main actor, on the model's task provider, and applies
    /// the result unless a newer mapping started meanwhile. Clears the rows at once while diagnostics are off.
    func recompute(for rendered: RenderedText, model: DiffViewerModel) {
        generation &+= 1
        let generation = generation
        guard model.settings.diagnosticsEnabled, let diagnostics = model.diagnostics else {
            overlay.replace([:])
            version += 1
            return
        }
        let right = SideFindings(paths: model.diagnosticFilePaths, findings: diagnostics.findingsByFile)
        let left = SideFindings(paths: model.diagnosticLeftFilePaths, findings: diagnostics.leftFindingsByFile)
        model.taskProvider.task {
            let rows = await DiagnosticRowMapper.rowsOffMain(for: rendered, left: left, right: right)
            guard generation == self.generation else { return }
            overlay.replace(rows)
            version += 1
        }
    }

    /// Presents ``DiagnosticFindingsList`` in an `NSPopover` anchored on the clicked row, which SwiftUI's `.popover`
    /// cannot anchor to.
    func showFindings(rowIndex: Int, findings: [Finding], anchorRect: NSRect, in view: NSView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = DiagnosticFindingsPopover.content(for: findings)
        self.popover = popover
        popover.show(relativeTo: anchorRect, of: view, preferredEdge: .minY)
    }

    /// Resolves a hover hit into `docs`' documentation styled with `palette`, joined by the findings underlined under
    /// the pointer; nil while no hover documentation model is attached.
    func hoverResolver(docs: HoverDocumentationModel?, palette: DiffPalette, settings: ViewerSettings)
        -> (@Sendable (HoverHit) async -> HoverDocument?)?
    {
        guard let docs else { return nil }
        return Self.hoverResolver(
            overlay: overlay,
            // Read as the hit resolves, so a change of setting reaches the next panel shown.
            material: { await settings.hoverPanelMaterial },
            documentation: { hit in
                let side: HoverQuerySide = hit.side == .new ? .new : .old
                guard
                    let content = await docs.hover(
                        fileIndex: hit.fileIndex, side: side, line: hit.line, utf16Column: hit.utf16Column)
                else { return nil }
                return HoverDocument.build(from: content, palette: palette)
            })
    }

    /// Resolves a hover hit into its documentation joined by the findings underlined under the pointer (book HOVER-14),
    /// or those findings alone when there is no documentation; nil when there is neither.
    nonisolated static func hoverResolver(
        overlay: DiagnosticOverlay, material: @escaping @Sendable () async -> HoverPanelMaterial,
        documentation: @escaping @Sendable (HoverHit) async -> HoverDocument?
    ) -> @Sendable (HoverHit) async -> HoverDocument? {
        { hit in
            let material = await material()
            let underPointer = overlay.row(hit.row)?.findings(underColumn: hit.utf16Column) ?? []
            let rowDiagnostics = underPointer.map { HoverDocument.DiagnosticEntry($0) }
            guard let document = await documentation(hit) else {
                guard !rowDiagnostics.isEmpty else { return nil }
                return HoverDocument(diagnostics: rowDiagnostics).presented(on: material)
            }
            return document.adding(diagnostics: rowDiagnostics).presented(on: material)
        }
    }
}

/// What a click on a decorated line number opens.
enum DiagnosticFindingsPopover {
    /// The popover's content for the findings of one row.
    static func content(for findings: [Finding]) -> NSHostingController<DiagnosticFindingsList> {
        NSHostingController(rootView: DiagnosticFindingsList(findings: findings))
    }
}

extension HoverDocument.DiagnosticEntry {
    nonisolated init(_ finding: Finding) {
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
