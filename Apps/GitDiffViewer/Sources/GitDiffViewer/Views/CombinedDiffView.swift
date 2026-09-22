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
/// The stack itself keeps zero spacing: a `Section`'s header and its own content are just two more children of
/// the same `LazyVStack`, so any spacing the stack applies falls *inside* every card, between its own header and
/// body, rather than only between cards. The 16pt gap between cards instead lives in a section footer of its own
/// (see ``FileCard``) -- present whether the body renders its full content or, folded, nothing at all, so the
/// gap survives a fold -- and header and body sit flush against each other at rest, letting ``FileCard`` tell a
/// header apart from a body that has scrolled out from under it purely by comparing the two edges that flushness
/// puts in the same place (see ``FileCard/isPinned``).
///
/// A header only ever looks detached from its body while it is genuinely floating: ``FileCardHeader`` switches its
/// own corner rounding and border on exactly when ``FileCard`` tells it it is pinned to the top of the scroll
/// content. Its shadow, though, stays on always, the same as its body's -- with the two pieces sitting flush and
/// each fully opaque, the shadow either piece would cast into the seam between them is hidden behind whichever
/// piece is drawn on top there, so only the outer silhouette shows through, reading as one shadow around the
/// whole card rather than two.
struct CombinedDiffView: View {
    let model: DiffViewerModel

    /// Named so ``FileCard``'s two halves can measure their own position in the scroll view's own coordinate
    /// space rather than the window's, independent of the toolbar height or how the window is placed on screen.
    nonisolated static let scrollSpace = "CombinedDiffView.scroll"
    /// The gap a pinned header rests under the toolbar with, matching the same gap every card keeps from the
    /// list's own edges.
    static let topInset: CGFloat = 16

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.renderedFiles) { file in
                        FileCard(file: file, model: model)
                            .id(file.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .coordinateSpace(name: Self.scrollSpace)
            // The list's own top inset moves here instead of living in the stack's padding: a pinned header pins
            // to the edge `contentMargins` carves out, so this one value keeps the resting gap under the toolbar.
            .contentMargins(.top, Self.topInset, for: .scrollContent)
            // Cards scroll beneath the toolbar; the soft edge blends that gap into the toolbar itself, so content
            // fades out approaching it rather than visibly running underneath a hard line. Genuine window chrome,
            // painted by AppKit above the scroll view's own layer -- unlike a view-level overlay, it never sits
            // between the content and its own shadow or the scroller, so neither is ever clipped by it.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: model.scrollRequest) { _, request in
                guard let request, request.row < model.renderedFiles.count else { return }
                withAnimation { proxy.scrollTo(model.renderedFiles[request.row].id, anchor: .top) }
            }
        }
    }
}

/// Scratch storage for a card's own measured edges (``FileCard/edges``), a plain reference type rather than
/// `@State` on purpose: mutating its properties never drives a view update on its own, only assigning `edges`
/// itself as a whole would. A scroll drags a card's header and body past each other every frame, so both edges
/// change every frame too -- were they `@State`, every one of those writes would re-evaluate ``FileCard``'s own
/// `body`, tearing down and rebuilding both ``FileCardHeader`` and ``FileCardBody`` (and, inside the header,
/// re-running its own non-trivial `summary`/diagnostics lookups) on every pixel of scroll, pinned or not. The
/// only thing a scroll frame should actually cost a re-render over is ``FileCard/isPinned`` itself flipping,
/// which happens at most twice per card per scroll pass -- see ``FileCard/refreshPinned()``.
private final class CardEdges {
    var headerMaxY: CGFloat = 0
    var bodyMinY: CGFloat = 0
}

/// One changed file's card: a pinned title header above its own scrolling body. Owns the one piece of state the
/// two halves can't measure on their own -- whether the header is genuinely floating, pinned above a body that
/// has scrolled out from under it, as opposed to merely sitting at rest right above it (``isPinned``) -- because
/// that comparison needs both halves' own positions at once, and a `Section`'s header and content are laid out as
/// two independent siblings that can't read each other's geometry directly.
private struct FileCard: View {
    let file: RenderedFile
    let model: DiffViewerModel

    /// This card's own header's bottom edge, and its own body's top edge, both measured in
    /// ``CombinedDiffView/scrollSpace`` by the two views themselves -- see ``isPinned``. Read fresh on every
    /// scroll frame without itself costing a re-render -- see ``CardEdges``.
    @State private var edges = CardEdges()
    /// Whether the header is floating, pinned to the top of the scroll content above a body that has scrolled
    /// out from under it, rather than sitting in its normal place directly above that body. The only geometry
    /// signal that is `@State`: every scroll frame recomputes it (``refreshPinned()``), but it is only ever
    /// *written* -- and so only ever costs a re-render -- the frames it actually flips.
    ///
    /// Position alone can't tell rest from pinned: at rest, the *first* card's header also sits with its own
    /// top edge exactly at the scroll content's top inset, the same place a pinned header settles. What actually
    /// changes when a header pins is that its body slides out from under it -- so this measures that instead.
    /// With zero spacing between header and body (see ``CombinedDiffView``'s own doc comment), at rest the body's
    /// own top edge sits exactly at the header's own bottom edge; once the header pins, it stops moving while the
    /// body keeps scrolling, so the body's own top edge passes above the header's own bottom edge. A one-point
    /// slack absorbs floating-point jitter between the two views' own geometry updates.
    @State private var isPinned = false

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }

    var body: some View {
        Section {
            FileCardBody(file: file, model: model, minYReported: reportBodyMinY)
        } header: {
            FileCardHeader(file: file, model: model, isPinned: isPinned, maxYReported: reportHeaderMaxY)
        } footer: {
            // The 16pt gap before the next card, as a footer rather than trailing padding on the body: a
            // footer is a section child of its own, present whether the body renders its full content or --
            // folded -- nothing at all, so the list's rhythm never collapses along with a folded card's body.
            Color.clear.frame(height: 16)
        }
        // Folding a card can leave its own header's bottom edge and its own body's top edge exactly where they
        // already were (the header's own height does not change, and the body collapses to nothing without
        // moving its own top) -- so folding is not guaranteed to itself trigger either geometry report above.
        // `isPinned` still needs to drop the moment a floating header is folded (its own `floats` already reacts
        // at once, through `isCollapsed`, directly), so this recomputes it explicitly on every fold and unfold.
        .onChange(of: isCollapsed) { refreshPinned() }
    }

    private func reportHeaderMaxY(_ maxY: CGFloat) {
        edges.headerMaxY = maxY
        refreshPinned()
    }

    private func reportBodyMinY(_ minY: CGFloat) {
        edges.bodyMinY = minY
        refreshPinned()
    }

    private func refreshPinned() {
        let newValue = !isCollapsed && edges.bodyMinY < edges.headerMaxY - 1
        if newValue != isPinned { isPinned = newValue }
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
    /// out from under it, rather than sitting in its normal place directly above that body. Computed by the
    /// owning ``FileCard``, which is the only thing that sees both this header's own position and its body's --
    /// see ``FileCard/isPinned``.
    let isPinned: Bool
    /// Reports this header's own bottom edge in ``CombinedDiffView/scrollSpace`` up to ``FileCard``, every time
    /// it moves.
    let maxYReported: (CGFloat) -> Void

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }
    private var summary: FileChangeSummary { model.changeSummary(for: file.path, rendered: file.rendered) }
    /// Whole-card chrome (full rounding, a border on every edge, a lift off the list) applies whenever the header
    /// carries the card on its own -- collapsed, with no body beneath it, or floating pinned above one.
    private var floats: Bool { isCollapsed || isPinned }
    /// A blurred backdrop earns its keep only while something is actually scrolling underneath this header --
    /// which is exactly ``isPinned``, not ``floats``: a *collapsed* header, even full-width and fully rounded,
    /// sits at rest in its own normal place with nothing moving beneath it (its body renders nothing, and
    /// nothing else overlaps it) until the moment it is itself scrolled to the top and pins. Gating on `floats`
    /// instead would put a live backdrop blur behind every collapsed header regardless -- ambient compositing
    /// cost that only compounds with however many files a large changeset folds, for a look no different from
    /// a plain opaque fill in the same colour, which is what a resting header (collapsed or not) uses instead.
    private var fill: AnyShapeStyle {
        isPinned ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }

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
        // The tint alone is clipped to the rounded shape here, ahead of `fill` below: a pinned header's own
        // rounded corners must stay fully opaque over whatever is scrolling underneath, which (see `fill`'s own
        // doc comment) rules out clipping `fill` itself the same way -- so only the tint, whose own square
        // corners would otherwise peek out past the rounded border as a visibly mismatched patch of colour,
        // gets its own clip here.
        .background(ChangeGlyph(summary.kind).color.opacity(0.08).clipShape(shape))
        .contentShape(Rectangle())
        // The single click must not wait for a possible double click: it folds at once, and the double click then
        // opens the file it folded.
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { model.toggleCollapsed(file.path) } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.pin(file.path) })
        .help("Click to fold, double-click to open \(model.displayPath(for: file.path))")
        .overlay(shape.strokeBorder(CardChrome.border, lineWidth: floats ? 1 : 0))
        // Always on, the same as the body's own -- see ``CombinedDiffView``'s own doc comment for why sitting
        // flush against an equally-shadowed, equally-opaque body hides the seam rather than doubling it. Cast
        // from a rounded silhouette of its own (`shape`), independent of `fill` below, so the shadow itself
        // reads as this header's rounded shape's rather than `fill`'s full square bounding box.
        .background { shape.fill(.black.opacity(0.0001)).shadow(color: .black.opacity(0.22), radius: 5, y: 2) }
        // The ONE fill behind everything above -- material while pinned, a plain opaque colour otherwise (see
        // `fill`'s own doc comment) -- deliberately left unclipped, covering the header's whole rectangular
        // footprint rather than only the rounded shape the border traces: a pinned header's own rounded corners
        // would otherwise cut two small triangles out of its content, right where whatever the list is
        // scrolling underneath would show through. Left as the one and only fill layer rather than adding a
        // second, separately clipped one behind it to plug just those corners: stacking two translucent
        // `regularMaterial` layers everywhere they overlap (which is nearly this header's whole area, not just
        // the corners) blurs measurably more heavily there than in the two corner slivers a second layer alone
        // would cover, reading as a visible seam between the two -- the background failing to "match" the
        // rounding the border and shadow above both trace. One layer, one blur intensity, everywhere; the
        // rounded look comes entirely from the border and shadow tracing `shape`, not from this fill agreeing
        // with their shape at all -- it does not need to, being the same flat colour and material whether a
        // given pixel falls inside that rounded silhouette or in the square corner just outside it.
        .background(fill)
        .background {
            // Reports this header's own bottom edge in the scroll view's coordinate space up to `FileCard`,
            // which compares it against its body's own top edge to know whether this header is pinned.
            Color.clear
                .onGeometryChange(
                    for: CGFloat.self, of: { $0.frame(in: .named(CombinedDiffView.scrollSpace)).maxY }
                ) { maxYReported($0) }
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
    /// Reports this body's own top edge in ``CombinedDiffView/scrollSpace`` up to ``FileCard``, every time it
    /// moves.
    let minYReported: (CGFloat) -> Void

    /// Text systems of this card, rebuilt when the file is re-rendered.
    @State private var layouts: CardLayouts?
    /// Width available to the panes, measured so the text views can be configured outside SwiftUI's layout pass.
    @State private var contentWidth: CGFloat = 0

    private var isCollapsed: Bool { model.collapsedFiles.contains(file.path) }

    var body: some View {
        Group {
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
                // Cards lift off the list, the way a sheet of paper would; the header carries the exact same
                // shadow always (not only while floating) -- see ``CombinedDiffView``'s own doc comment for why
                // that, not a shadow on one piece alone, is what keeps the seam between them from showing.
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                .onChange(of: file.rendered.id, initial: true) { layouts = CardLayouts(rendered: file.rendered) }
            }
        }
        .background {
            // Reports this body's own top edge up to `FileCard`, which compares it against the header's own
            // bottom edge to know whether that header is pinned.
            Color.clear
                .onGeometryChange(
                    for: CGFloat.self, of: { $0.frame(in: .named(CombinedDiffView.scrollSpace)).minY }
                ) { minYReported($0) }
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
