import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

struct DiffDetailView: View {
    let model: DiffViewerModel

    private var showsTabs: Bool { !model.tabs.tabs.isEmpty }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A bar rather than a row stacked above the content: the card list scrolls beneath the tabs as it does
            // beneath the toolbar, and the system extends its scroll edge effect over them.
            .safeAreaBar(edge: .top, spacing: 0) {
                if showsTabs { TabBarView(model: model) }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.detailState {
            case .cards:
                CombinedDiffView(model: model)
            case .file(let rendered):
                // The AppKit panes stay below the bar: SwiftUI hands neither the bar's inset nor its edge effect to
                // an NSScrollView, so a divider closes the bar here instead.
                VStack(spacing: 0) {
                    if showsTabs { Divider() }
                    panes(for: rendered)
                }
            case .loading:
                ProgressView("Comparing…")
            case .error(let error):
                ContentUnavailableView(
                    "Cannot compare", systemImage: "exclamationmark.triangle", description: Text(error))
            case .noChanges:
                ContentUnavailableView(
                    "No changes", systemImage: "checkmark.circle",
                    description: Text("Every file under the selection is identical on both sides."))
            case .noSelection:
                ContentUnavailableView(
                    "No file selected", systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a file in either explorer."))
            case .noSources:
                ContentUnavailableView(
                    "No sources", systemImage: "folder.badge.questionmark",
                    description: Text("Pick the two sides to compare."))
        }
    }

    @ViewBuilder private func panes(for rendered: RenderedDiff) -> some View {
        switch model.settings.mode {
            case .inline:
                if let unified = rendered.unified {
                    DiagnosticDiffTextView(
                        model: model,
                        rendered: unified,
                        gutter: .dual,
                        keepsScrollPosition: rendered.keepsScrollPosition,
                        wrapsLines: model.settings.wrapsLines,
                        wrapColumn: model.settings.wrapColumn,
                        showsMinimap: model.settings.showsMinimap,
                        scrollRequest: model.scrollRequest,
                        onGapDrag: { marker, base, lines in model.adjustGap(marker, from: base, byLines: lines) },
                        currentExpansion: { model.expansion(of: $0) },
                        onDisplayed: { model.noteDisplayed(rendered.id) }
                    )
                }
            case .split, .stacked:
                if let old = rendered.old, let new = rendered.new {
                    SplitDiffView(
                        model: model,
                        old: old,
                        new: new,
                        keepsScrollPosition: rendered.keepsScrollPosition,
                        isStacked: model.settings.mode == .stacked,
                        wrapsLines: model.settings.wrapsLines,
                        wrapColumn: model.settings.wrapColumn,
                        showsMinimap: model.settings.showsMinimap,
                        syncsScrolling: model.settings.syncsScrolling,
                        scrollRequest: model.scrollRequest,
                        onGapDrag: { marker, base, lines in model.adjustGap(marker, from: base, byLines: lines) },
                        currentExpansion: { model.expansion(of: $0) },
                        onDisplayed: { model.noteDisplayed(rendered.id) }
                    )
                }
        }
    }
}

private struct SplitDiffView: View {
    let model: DiffViewerModel
    let old: RenderedText
    let new: RenderedText
    let keepsScrollPosition: Bool
    let isStacked: Bool
    let wrapsLines: Bool
    let wrapColumn: Int
    let showsMinimap: Bool
    let syncsScrolling: Bool
    let scrollRequest: ScrollRequest?
    let onGapDrag: (GapMarker, GapExpansion, Int) -> Void
    let currentExpansion: (GapKey) -> GapExpansion
    let onDisplayed: () -> Void

    @State private var controller = SplitPaneController()

    var body: some View {
        let layout = isStacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            DiagnosticDiffTextView(
                model: model, rendered: old, gutter: .old, keepsScrollPosition: keepsScrollPosition,
                wrapsLines: wrapsLines, wrapColumn: wrapColumn, showsMinimap: showsMinimap,
                syncsScrolling: syncsScrolling, scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, currentExpansion: currentExpansion
            )
            Divider()
            DiagnosticDiffTextView(
                model: model, rendered: new, gutter: .new, keepsScrollPosition: keepsScrollPosition,
                wrapsLines: wrapsLines, wrapColumn: wrapColumn, showsMinimap: showsMinimap,
                syncsScrolling: syncsScrolling, scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, currentExpansion: currentExpansion
            )
        }
        .onAppear { controller.wrapsLines = wrapsLines }
        .onChange(of: isStacked) { controller.wrapsLines = wrapsLines }
    }
}
