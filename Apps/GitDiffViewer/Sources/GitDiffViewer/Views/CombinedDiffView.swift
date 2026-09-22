import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Every changed file of the selection as a card: a title, then the file's isolated changes in the current layout.
/// Each card's title bar is a `Section` header, pinned to the top of the scroll view while any part of its card
/// is still on screen -- a fold stays reachable without scrolling back up to it, the way Xcode's own file list
/// pins a group header. ``FileCardHeader`` and ``FileCardBody`` split what used to be one `VStack` because a
/// pinned `Section` header and its content are laid out (and can be on screen) independently: each carries its
/// own half of the card's chrome -- the header's own top rounding, the body's own bottom rounding, both sharing
/// the same corner radius and border colour -- so the two still read as one continuous card whether the header is
/// sitting in its normal place or floating pinned above a scrolled body.
///
/// A header only ever looks detached from its body while it is genuinely floating: ``FileCardHeader`` measures its
/// own position against ``scrollSpace`` and switches its own chrome (full rounding, border, shadow) on exactly when
/// it is pinned to the top of the scroll content, matching ``topInset``. At rest, right above its body, it drops
/// its own bottom edge and shadow so the seam is carried by the body's own border alone -- one line, not two.
struct CombinedDiffView: View {
    let model: DiffViewerModel

    /// Named so ``FileCardHeader`` can measure its own position in the scroll view's own coordinate space rather
    /// than the window's, independent of the toolbar height or how the window is placed on screen.
    nonisolated static let scrollSpace = "CombinedDiffView.scroll"
    /// The gap a pinned header rests under the toolbar with, matching the same gap every card keeps from the list's
    /// own edges: one `.contentMargins(.top)` value plays double duty as that resting gap and as the threshold a
    /// header's own measured position is compared against to decide it is pinned (see ``FileCardHeader/isPinned``).
    static let topInset: CGFloat = 16

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.renderedFiles) { file in
                        Section {
                            FileCardBody(file: file, model: model)
                        } header: {
                            FileCardHeader(file: file, model: model)
                        }
                        .id(file.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: Self.scrollSpace)
            // The list's own top inset moves here instead of living in the stack's padding: a pinned header pins
            // to the edge `contentMargins` carves out, so this one value both keeps the resting gap under the
            // toolbar and, doubling as `topInset`, is what a header compares its own position against to know it
            // is pinned (Fix 2 and Fix 3 below share this one mechanism rather than two).
            .contentMargins(.top, Self.topInset, for: .scrollContent)
            // Cards scroll beneath the toolbar; the soft edge keeps the bar legible without a hard line.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: model.scrollRequest) { _, request in
                guard let request, request.row < model.renderedFiles.count else { return }
                withAnimation { proxy.scrollTo(model.renderedFiles[request.row].id, anchor: .top) }
            }
        }
    }
}

/// The card's own corner radius and border colour, shared between ``FileCardHeader`` and ``FileCardBody`` so the
/// two pieces read as one card.
private enum CardChrome {
    static let cornerRadius: CGFloat = 10
    static var border: Color { Color(nsColor: .separatorColor) }
}

/// The pinned half of a card: title, fold state, badges. A single click folds the file away, a double click opens
/// it on its own. The tint says at a glance what kind of change the file holds, faintly enough to stay behind the
/// text.
private struct FileCardHeader: View {
    let file: RenderedFile
    let model: DiffViewerModel

    /// Whether this header is currently floating, pinned to the top of the scroll content above a body scrolled
    /// out from under it, rather than sitting in its normal place directly above that body. Measured, not
    /// inferred: a pinned `Section` header's own `minY` in ``CombinedDiffView/scrollSpace`` settles at
    /// ``CombinedDiffView/topInset`` and stays clamped there for as long as it is pinned, while at rest (or while
    /// merely scrolling past, not yet pinned) it is greater. A half-point slack absorbs floating-point jitter
    /// between geometry updates.
    @State private var isPinned = false

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }
    private var summary: FileChangeSummary { model.changeSummary(for: file.path, rendered: file.rendered) }
    /// Whole-card chrome (full rounding, a border on every edge, a lift off the list) applies whenever the header
    /// carries the card on its own -- collapsed, with no body beneath it, or floating pinned above one.
    private var floats: Bool { isCollapsed || isPinned }

    var body: some View {
        HStack {
            // A dedicated expand/collapse pair rather than a rotated chevron, morphing through a symbol
            // replacement so the fold reads as one continuous gesture with the card's own collapse animation.
            Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.18), value: isCollapsed)
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Image(systemName: "doc.text")
            Text(model.displayPath(for: file.path))
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Spacer()
            if model.settings.diagnosticsEnabled {
                DiagnosticCountBadge(counts: model.diagnosticSeverityCounts(for: file.path))
            }
            ChangeBadge(summary: summary)
        }
        .padding(.leading, 12)
        // The badge sits as far from the card's edge as from its top and bottom.
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(ChangeGlyph(summary.kind).color.opacity(0.08))
        // The header is frosted on its own now that it can float apart from the body beneath it; only the code
        // sits on the theme's own colour, so the title strip takes its light from the list instead of hiding it.
        .background(.regularMaterial)
        .contentShape(Rectangle())
        // The single click must not wait for a possible double click: it folds at once, and the double click then
        // opens the file it folded.
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.toggleCollapsed(file.path) } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.pin(file.path) })
        .help("Click to fold, double-click to open \(model.displayPath(for: file.path))")
        .clipShape(shape)
        .overlay(shape.strokeBorder(CardChrome.border, lineWidth: floats ? 1 : 0))
        // A floating header (collapsed, or pinned above a scrolled body) sits over whatever the list is scrolling
        // underneath it; its own rounded corners cut two small triangles out of its otherwise-opaque material,
        // and without a backing of their own those would show a sliver of scrolling text right through the
        // corner. This second, *unclipped* material fill sits behind the already-clipped, already-rounded header
        // above -- squared off to the header's full bounding box -- so what shows through the corner cut is more
        // frosted glass, not raw content. Only needed while floating: at rest a header has nothing scrolling
        // underneath its own corners, just its own body sitting flush beneath it.
        .background { if floats { Rectangle().fill(.regularMaterial) } }
        .shadow(color: .black.opacity(floats ? 0.22 : 0), radius: floats ? 5 : 0, y: 2)
        .background {
            // Measures this header's own resting place in the scroll view's coordinate space to tell a pinned,
            // floating header from one still sitting in its normal place above its body -- see `isPinned`.
            Color.clear
                .onGeometryChange(
                    for: CGFloat.self, of: { $0.frame(in: .named(CombinedDiffView.scrollSpace)).minY }
                ) { minY in
                    isPinned = !isCollapsed && minY <= CombinedDiffView.topInset + 0.5
                }
        }
    }

    /// Rounded on top always; rounded on the bottom too exactly while the header carries the whole card on its
    /// own (``floats``) -- collapsed, with no body beneath it, or pinned and floating above one it has scrolled
    /// away from. Flat and square on the bottom the rest of the time, so it reads as sitting directly on its body
    /// rather than as a card of its own stacked on top of it.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: CardChrome.cornerRadius, bottomLeadingRadius: floats ? CardChrome.cornerRadius : 0,
            bottomTrailingRadius: floats ? CardChrome.cornerRadius : 0, topTrailingRadius: CardChrome.cornerRadius)
    }
}

/// The scrolling half of a card: the file's isolated changes in the current layout, beneath a divider. Empty
/// (and chromeless) while the file is folded, so ``FileCardHeader`` alone carries the card's full rounding then.
private struct FileCardBody: View {
    let file: RenderedFile
    let model: DiffViewerModel

    /// Text systems of this card, rebuilt when the file is re-rendered.
    @State private var layouts: CardLayouts?
    /// Width available to the panes, measured so the text views can be configured outside SwiftUI's layout pass.
    @State private var contentWidth: CGFloat = 0

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }

    var body: some View {
        if !isCollapsed {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                panes
                    .background(Color(nsColor: model.palette.background))
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { contentWidth = $0 }
            }
            .background(.regularMaterial)
            .clipShape(shape)
            .overlay(shape.strokeBorder(CardChrome.border))
            // Cards lift off the list, the way a sheet of paper would; the body carries its own half of that
            // lift so the seam where it meets the (independently laid out) header never looks flat by comparison.
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .onChange(of: file.rendered.id, initial: true) { layouts = CardLayouts(rendered: file.rendered) }
        }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: CardChrome.cornerRadius,
            bottomTrailingRadius: CardChrome.cornerRadius, topTrailingRadius: 0)
    }

    @ViewBuilder private var panes: some View {
        let layouts = layouts ?? CardLayouts(rendered: file.rendered)
        let wrapMode = WrapMode(wrapsLines: model.settings.wrapsLines, column: model.settings.wrapColumn)
        let displayed = { model.noteDisplayed(file.rendered.id) }
        switch model.settings.mode {
            case .inline:
                if layouts.unified != nil {
                    EmbeddedDiffTextView(
                        layouts: layouts, side: .unified, gutter: .dual, width: contentWidth, wrapMode: wrapMode,
                        onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed,
                        hoverEnabled: hoverEnabled, hoverResolver: hoverResolver)
                }
            case .split, .stacked:
                if layouts.old != nil, layouts.new != nil {
                    let isStacked = model.settings.mode == .stacked
                    let paneWidth = isStacked ? contentWidth : max((contentWidth - 1) / 2, 0)
                    let stack =
                        isStacked
                        ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                    stack {
                        EmbeddedDiffTextView(
                            layouts: layouts, side: .old, gutter: .old, width: paneWidth, wrapMode: wrapMode,
                            onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed,
                            hoverEnabled: hoverEnabled, hoverResolver: hoverResolver
                        )
                        .frame(maxWidth: .infinity)
                        Divider()
                        EmbeddedDiffTextView(
                            layouts: layouts, side: .new, gutter: .new, width: paneWidth, wrapMode: wrapMode,
                            onGapDrag: drag, currentExpansion: expansion, onDisplayed: displayed,
                            hoverEnabled: hoverEnabled, hoverResolver: hoverResolver
                        )
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

    private var hoverEnabled: Bool {
        model.settings.showsHoverDocumentation && model.hoverDocs != nil
    }

    /// Resolves a hover hit through ``DiffComparison/HoverDocumentationModel`` and structures and colors its
    /// markdown for the panel, the same as ``DiagnosticDiffTextView``'s own resolver. Each rendered row already
    /// carries the comparison's global `fileIndex` (``RenderPipeline`` renders every card with its own offset into
    /// the changeset), so no translation from this card's own path is needed.
    private var hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? {
        guard let hoverDocs = model.hoverDocs else { return nil }
        let palette = model.palette
        return { hit in
            let side: HoverQuerySide = hit.side == .new ? .new : .old
            guard
                let content = await hoverDocs.hover(
                    fileIndex: hit.fileIndex, side: side, line: hit.line, utf16Column: hit.utf16Column)
            else { return nil }
            return HoverDocument.build(from: content, palette: palette)
        }
    }
}

/// This file's warning and error counts, in the same idiom as the header's own +/− line counts. Hidden when the
/// file has neither.
private struct DiagnosticCountBadge: View {
    let counts: DiagnosticSeverityCounts

    var body: some View {
        if !counts.isEmpty {
            HStack(spacing: 6) {
                if counts.warnings > 0 {
                    Label("\(counts.warnings)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
                if counts.errors > 0 {
                    Label("\(counts.errors)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .fixedSize()
                }
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.monospacedDigit())
        }
    }
}
