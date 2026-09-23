import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Every changed file of the selection as a card, in the current layout. Each card's header sticks below the
/// window's top bars while the card scrolls past them, so a half-scrolled file can still be folded.
struct CombinedDiffView: View {
    let model: DiffViewerModel

    /// The space between cards and around the list, and between a sticking header and the bars above it.
    static let topInset: CGFloat = 16

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.renderedFiles) { file in
                        FileCard(file: file, model: model)
                            // Inside the scroll target, so scrolling to a card lands it at rest below the bars.
                            .padding(.top, Self.topInset)
                            .id(file.id)
                    }
                }
                .padding([.horizontal, .bottom], Self.topInset)
            }
            // System chrome rather than a painted strip, so it never clips a card's shadow or the scroller.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: model.scrollRequest) { _, request in
                guard let request, request.row < model.renderedFiles.count else { return }
                withAnimation { proxy.scrollTo(model.renderedFiles[request.row].id, anchor: .top) }
            }
        }
    }
}

/// One changed file. Reads only what its header shows, so the change summary and the diagnostic counts are
/// computed again only when those inputs change; folds and pane settings re-evaluate ``FileCardFrame`` alone.
private struct FileCard: View {
    let file: RenderedFile
    let model: DiffViewerModel

    var body: some View {
        FileCardFrame(file: file, title: CardTitle(file: file, model: model), model: model)
    }
}

/// What a card's header shows.
private struct CardTitle: Equatable {
    let displayPath: String
    let summary: FileChangeSummary
    /// Nil while diagnostics are off.
    let diagnostics: DiagnosticSeverityCounts?

    init(file: RenderedFile, model: DiffViewerModel) {
        displayPath = model.displayPath(for: file.path)
        summary = model.changeSummary(for: file.path, rendered: file.rendered)
        diagnostics = model.settings.diagnosticsEnabled ? model.diagnosticSeverityCounts(for: file.path) : nil
    }
}

/// How a card's panes lay out and behave.
private struct PaneOptions: Equatable {
    let mode: ViewMode
    let wrapMode: WrapMode
    let showsHover: Bool
}

/// A card's fold state and pane options, read apart from its title so a fold never recomputes the title.
private struct FileCardFrame: View {
    let file: RenderedFile
    let title: CardTitle
    let model: DiffViewerModel

    var body: some View {
        let settings = model.settings
        StickyCard(
            file: file, title: title, isCollapsed: model.collapsedFiles.contains(file.path),
            options: PaneOptions(
                mode: settings.mode, wrapMode: WrapMode(wrapsLines: settings.wrapsLines, column: settings.wrapColumn),
                showsHover: settings.showsHoverDocumentation && model.hoverDocs != nil),
            model: model)
    }
}

/// Hosts a card's header and body in a ``StickyCardView``. Every input that changes the card's height is a
/// property here, so SwiftUI measures the card again whenever one changes.
private struct StickyCard: NSViewRepresentable {
    let file: RenderedFile
    let title: CardTitle
    let isCollapsed: Bool
    let options: PaneOptions
    let model: DiffViewerModel

    func makeCoordinator() -> CardHosts {
        CardHosts(card: self)
    }

    func makeNSView(context: Context) -> StickyCardView {
        let view = StickyCardView(header: context.coordinator.header.view, body: context.coordinator.body.view)
        view.stickyGap = CombinedDiffView.topInset
        return view
    }

    func updateNSView(_ view: StickyCardView, context: Context) {
        if context.coordinator.update(to: self) { view.invalidateIntrinsicContentSize() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: StickyCardView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let heights = context.coordinator.heights(forWidth: width)
        view.headerHeight = heights.header
        return CGSize(width: width, height: heights.header + heights.body)
    }
}

/// A card's header and body heights at one width.
private struct CardHeights: Equatable {
    let header: CGFloat
    let body: CGFloat
}

/// A card's two hosting controllers and its text systems, which it builds once per render.
private final class CardHosts {
    let header: NSHostingController<FileCardHeader>
    let body: NSHostingController<FileCardBody>
    private var card: StickyCard
    private var layouts: CardLayouts?
    private var width: CGFloat = 0
    private var bodyInputs: BodyInputs?
    private var measured: (key: MeasureKey, heights: CardHeights)?

    /// What the body is built from; the body is rebuilt only when these change.
    private struct BodyInputs: Equatable {
        let renderID: RenderedDiff.ID
        let isCollapsed: Bool
        let options: PaneOptions
        let width: CGFloat
    }

    private struct MeasureKey: Equatable {
        let body: BodyInputs
        let title: CardTitle
    }

    init(card: StickyCard) {
        self.card = card
        header = NSHostingController(rootView: Self.header(for: card))
        body = NSHostingController(rootView: FileCardBody(content: nil, width: 0, options: card.options))
        // The card sizes and places both hosts, and the window's bars never inset a card's content.
        header.sizingOptions = []
        header.safeAreaRegions = []
        body.sizingOptions = []
        body.safeAreaRegions = []
        refreshBody()
    }

    /// Takes the card's latest inputs.
    /// - Returns: Whether the card's height may have changed.
    func update(to card: StickyCard) -> Bool {
        let previous = self.card
        self.card = card
        if previous.title != card.title || previous.isCollapsed != card.isCollapsed {
            header.rootView = Self.header(for: card)
        }
        refreshBody()
        return previous.title != card.title || previous.isCollapsed != card.isCollapsed
            || previous.options != card.options || previous.file.rendered.id != card.file.rendered.id
    }

    /// The header's and the body's heights at `width`, rounded up to whole points so the seam stays on the pixel
    /// grid; measured again only when `width` or an input changes.
    func heights(forWidth width: CGFloat) -> CardHeights {
        if width != self.width {
            self.width = width
            refreshBody()
        }
        let key = MeasureKey(body: currentBodyInputs(), title: card.title)
        if let measured, measured.key == key { return measured.heights }
        let fitting = CGSize(width: width, height: .greatestFiniteMagnitude)
        let heights = CardHeights(
            header: header.sizeThatFits(in: fitting).height.rounded(.up),
            body: card.isCollapsed ? 0 : body.sizeThatFits(in: fitting).height.rounded(.up))
        measured = (key, heights)
        return heights
    }

    private func currentBodyInputs() -> BodyInputs {
        BodyInputs(
            renderID: card.file.rendered.id, isCollapsed: card.isCollapsed, options: card.options, width: width)
    }

    private func refreshBody() {
        let inputs = currentBodyInputs()
        guard inputs != bodyInputs else { return }
        bodyInputs = inputs
        guard !card.isCollapsed else {
            body.rootView = FileCardBody(content: nil, width: width, options: card.options)
            return
        }
        let rendered = card.file.rendered
        let layouts = layouts.flatMap { $0.renderID == rendered.id ? $0 : nil } ?? CardLayouts(rendered: rendered)
        self.layouts = layouts
        body.rootView = FileCardBody(
            content: PaneContent(layouts: layouts, rendered: rendered, model: card.model), width: width,
            options: card.options)
    }

    private static func header(for card: StickyCard) -> FileCardHeader {
        let model = card.model
        let path = card.file.path
        return FileCardHeader(
            title: card.title, isCollapsed: card.isCollapsed,
            toggle: { withAnimation(.easeOut(duration: 0.12)) { model.toggleCollapsed(path) } },
            open: { model.pin(path) })
    }
}

/// A card's text systems, the panes' background, and what the panes call back into.
private struct PaneContent {
    let layouts: CardLayouts
    let background: NSColor
    let drag: (GapMarker, GapExpansion, Int) -> Void
    let expansion: (GapKey) -> GapExpansion
    let displayed: () -> Void
    let hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)?

    init(layouts: CardLayouts, rendered: RenderedDiff, model: DiffViewerModel) {
        let id = rendered.id
        self.layouts = layouts
        background = model.palette.background
        drag = { marker, base, lines in model.adjustGap(marker, from: base, byLines: lines) }
        expansion = { model.expansion(of: $0) }
        displayed = { model.noteDisplayed(id) }
        hoverResolver = Self.hoverResolver(docs: model.hoverDocs, palette: model.palette)
    }

    /// Resolves a hover hit and colors its documentation for the panel. Each row carries the comparison's global
    /// `fileIndex`, so the hit needs no translation from this card's path.
    private static func hoverResolver(docs: HoverDocumentationModel?, palette: DiffPalette) -> (
        @Sendable (HoverHit) async -> HoverDocument?
    )? {
        guard let docs else { return nil }
        return { hit in
            let side: HoverQuerySide = hit.side == .new ? .new : .old
            guard
                let content = await docs.hover(
                    fileIndex: hit.fileIndex, side: side, line: hit.line, utf16Column: hit.utf16Column)
            else { return nil }
            return HoverDocument.build(from: content, palette: palette)
        }
    }
}

/// A card's title bar: fold glyph, path and badges on an opaque tint of the change kind. A click folds the card
/// and a double click opens the file on its own.
private struct FileCardHeader: View {
    let title: CardTitle
    let isCollapsed: Bool
    let toggle: () -> Void
    let open: () -> Void

    var body: some View {
        HStack {
            // A symbol replacement rather than a rotated chevron, so the fold reads as one gesture.
            Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.18), value: isCollapsed)
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Image(systemName: "doc.text")
            Text(title.displayPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
            Spacer()
            if let diagnostics = title.diagnostics {
                DiagnosticCountBadge(counts: diagnostics)
            }
            ChangeBadge(summary: title.summary)
        }
        .padding(.leading, 12)
        // The badge sits as far from the card's edge as from its top and bottom.
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // Opaque, so nothing behind the header needs a blur; the card's clip rounds it.
        .background(ChangeGlyph(title.summary.kind).color.opacity(0.08))
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        // The single click must not wait for a double click: it folds at once, and the double click then opens.
        .onTapGesture(perform: toggle)
        .simultaneousGesture(TapGesture(count: 2).onEnded(open))
        .help("Click to fold, double-click to open \(title.displayPath)")
    }
}

/// A card's body: the seam, then the file's isolated changes in the current layout. Renders nothing without
/// content, which is how a folded card unmounts its panes.
private struct FileCardBody: View {
    let content: PaneContent?
    /// The card's width, which the panes need before SwiftUI lays them out.
    let width: CGFloat
    let options: PaneOptions

    var body: some View {
        if let content {
            VStack(spacing: 0) {
                // The one seam between header and body, inset so the card's outline never doubles its ends.
                Divider()
                    .padding(.horizontal, StickyCardView.lineWidth)
                    .background(Color(nsColor: .windowBackgroundColor))
                panes(content)
                    .background(Color(nsColor: content.background))
            }
        }
    }

    @ViewBuilder private func panes(_ content: PaneContent) -> some View {
        switch options.mode {
            case .inline:
                if content.layouts.unified != nil {
                    pane(content, side: .unified, gutter: .dual, width: width)
                }
            case .split, .stacked:
                if content.layouts.old != nil, content.layouts.new != nil {
                    let isStacked = options.mode == .stacked
                    let paneWidth = isStacked ? width : max((width - 1) / 2, 0)
                    let stack =
                        isStacked
                        ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                    stack {
                        pane(content, side: .old, gutter: .old, width: paneWidth)
                            .frame(maxWidth: .infinity)
                        Divider()
                        pane(content, side: .new, gutter: .new, width: paneWidth)
                            .frame(maxWidth: .infinity)
                    }
                }
        }
    }

    private func pane(_ content: PaneContent, side: RenderedSide, gutter: GutterStyle, width: CGFloat)
        -> EmbeddedDiffTextView
    {
        EmbeddedDiffTextView(
            layouts: content.layouts, side: side, gutter: gutter, width: width, wrapMode: options.wrapMode,
            onGapDrag: content.drag, currentExpansion: content.expansion, onDisplayed: content.displayed,
            hoverEnabled: options.showsHover, hoverResolver: content.hoverResolver)
    }
}

/// This file's warning and error counts, in the same idiom as the header's +/− line counts. Hidden when the file
/// has neither.
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
