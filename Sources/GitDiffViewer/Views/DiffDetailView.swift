import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

struct DiffDetailView: View {
    let model: DiffViewerModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.tabs.tabs.isEmpty {
                TabBarView(model: model)
                Divider()
            }
            switch model.detailState {
            case .cards:
                CombinedDiffView(model: model)
            case .file(let rendered):
                panes(for: rendered)
            case .loading:
                ProgressView("Comparing…")
            case .error(let error):
                ContentUnavailableView("Cannot compare", systemImage: "exclamationmark.triangle", description: Text(error))
            case .noChanges:
                ContentUnavailableView("No changes", systemImage: "checkmark.circle", description: Text("Every file under the selection is identical on both sides."))
            case .noSelection:
                ContentUnavailableView("No file selected", systemImage: "doc.text.magnifyingglass", description: Text("Select a file in either explorer."))
            case .noSources:
                ContentUnavailableView("No sources", systemImage: "folder.badge.questionmark", description: Text("Pick the two sides to compare."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func panes(for rendered: RenderedDiff) -> some View {
        switch model.settings.mode {
        case .inline:
            if let unified = rendered.unified {
                DiffTextView(
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
            DiffTextView(
                rendered: old, gutter: .old, keepsScrollPosition: keepsScrollPosition, wrapsLines: wrapsLines,
                wrapColumn: wrapColumn, showsMinimap: showsMinimap, syncsScrolling: syncsScrolling,
                scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, currentExpansion: currentExpansion
            )
            Divider()
            DiffTextView(
                rendered: new, gutter: .new, keepsScrollPosition: keepsScrollPosition, wrapsLines: wrapsLines,
                wrapColumn: wrapColumn, showsMinimap: showsMinimap, syncsScrolling: syncsScrolling,
                scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, currentExpansion: currentExpansion
            )
        }
        .onAppear { controller.wrapsLines = wrapsLines }
        .onChange(of: isStacked) { controller.wrapsLines = wrapsLines }
    }
}
