import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Every changed file of the selection as a card: a title, then the file's isolated changes in the current layout.
struct CombinedDiffView: View {
    let model: DiffViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.renderedFiles) { file in
                        FileCard(file: file, model: model)
                            .id(file.id)
                    }
                }
                .padding(16)
            }
            // Cards scroll beneath the toolbar; the soft edge keeps the bar legible without a hard line.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: model.scrollRequest) { _, request in
                guard let request, request.row < model.renderedFiles.count else { return }
                withAnimation { proxy.scrollTo(model.renderedFiles[request.row].id, anchor: .top) }
            }
        }
    }
}

private struct FileCard: View {
    let file: RenderedFile
    let model: DiffViewerModel

    /// Text systems of this card, rebuilt when the file is re-rendered.
    @State private var layouts: CardLayouts?
    /// Width available to the panes, measured so the text views can be configured outside SwiftUI's layout pass.
    @State private var contentWidth: CGFloat = 0

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }

    private var summary: FileChangeSummary { model.changeSummary(for: file.path, rendered: file.rendered) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                panes
                    .background(Color(nsColor: model.palette.background))
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
            }
        }
        // The card itself is frosted; only the code sits on the theme's own colour, so the title strip above it
        // takes its light from the list instead of hiding it.
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // Cards lift off the list, the way a sheet of paper would.
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        .onChange(of: file.rendered.id, initial: true) { layouts = CardLayouts(rendered: file.rendered) }
    }

    /// A single click folds the file away, a double click opens it on its own. The tint says at a glance what
    /// kind of change the file holds, faintly enough to stay behind the text.
    private var header: some View {
        HStack {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .foregroundStyle(.secondary)
            Image(systemName: "doc.text")
            Text(model.displayPath(for: file.path))
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Spacer()
            ChangeBadge(summary: summary)
        }
        .padding(.leading, 12)
        // The badge sits as far from the card's edge as from its top and bottom.
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(ChangeGlyph(summary.kind).color.opacity(0.08))
        .contentShape(Rectangle())
        // The single click must not wait for a possible double click: it folds at once, and the double click then
        // opens the file it folded.
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.toggleCollapsed(file.path) } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.pin(file.path) })
        .help("Click to fold, double-click to open \(model.displayPath(for: file.path))")
    }

    @ViewBuilder private var panes: some View {
        let layouts = layouts ?? CardLayouts(rendered: file.rendered)
        let wrapMode = WrapMode(wrapsLines: model.settings.wrapsLines, column: model.settings.wrapColumn)
        let displayed = { model.noteDisplayed(file.rendered.id) }
        switch model.settings.mode {
        case .inline:
            if layouts.unified != nil {
                EmbeddedDiffTextView(layouts: layouts, side: .unified, gutter: .dual, width: contentWidth, wrapMode: wrapMode, onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed)
            }
        case .split, .stacked:
            if layouts.old != nil, layouts.new != nil {
                let isStacked = model.settings.mode == .stacked
                let paneWidth = isStacked ? contentWidth : max((contentWidth - 1) / 2, 0)
                let stack = isStacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                stack {
                    EmbeddedDiffTextView(layouts: layouts, side: .old, gutter: .old, width: paneWidth, wrapMode: wrapMode, onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed)
                        .frame(maxWidth: .infinity)
                    Divider()
                    EmbeddedDiffTextView(layouts: layouts, side: .new, gutter: .new, width: paneWidth, wrapMode: wrapMode, onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func drag(_ marker: GapMarker, _ base: GapExpansion, _ lines: Int) {
        model.adjustGap(marker, from: base, byLines: lines)
    }

    private func expansion(_ key: GapKey) -> GapExpansion {
        model.expansion(of: key)
    }
}
