import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI
import os

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
    let badgeScheme: BadgeScheme
    /// Where this file's change stands in git: filled when committed or staged, stroked when unstaged or untracked.
    let badgeState: BadgeChangeState

    init(file: RenderedFile, model: DiffViewerModel) {
        displayPath = model.displayPath(for: file.path)
        summary = model.changeSummary(for: file.path, rendered: file.rendered)
        diagnostics = model.settings.diagnosticsEnabled ? model.diagnosticSeverityCounts(for: file.path) : nil
        badgeScheme = model.settings.badgeScheme
        badgeState = model.badgeState(ofPath: file.path)
    }
}

/// How a card's panes lay out and behave.
private struct PaneOptions: Equatable {
    let layout: CardLayout
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
        let isCollapsed = model.collapsedFiles.contains(file.path)
        FoldingCard(
            foldProgress: isCollapsed ? 1 : 0,
            card: StickyCard(
                file: file, title: title, isCollapsed: isCollapsed,
                options: PaneOptions(
                    layout: settings.mode.cardLayout,
                    wrapMode: WrapMode(wrapsLines: settings.wrapsLines, column: settings.wrapColumn),
                    showsHover: settings.showsHoverDocumentation && model.hoverDocs != nil),
                model: model)
        )
        // Set here, in the list's own graph, so a fold animates wherever it starts: an animation begun in the
        // header's hosting view or in the toolbar does not reliably reach this graph.
        .animation(StickyCard.fold, value: isCollapsed)
    }
}

/// A card whose height follows its fold frame by frame. SwiftUI interpolates `foldProgress` and evaluates this view on
/// every frame of a fold, so the list lays out again at each height and the cards below follow the card's edge. A
/// representable's own animatable data is not interpolated.
@Animatable
private struct FoldingCard: View {
    /// 0 unfolded, 1 folded.
    var foldProgress: CGFloat
    @AnimatableIgnored var card: StickyCard

    var body: some View {
        var card = card
        card.foldProgress = foldProgress
        return card
    }
}

/// Hosts a card's header and body in a ``StickyCardView``. Every input that changes the card's height is a
/// property here, so SwiftUI measures the card again whenever one changes.
private struct StickyCard: NSViewRepresentable {
    /// How a card folds and unfolds: its bottom edge, and every card below it, ease out together.
    static let fold: Animation = .easeOut(duration: 0.2)

    let file: RenderedFile
    let title: CardTitle
    let isCollapsed: Bool
    let options: PaneOptions
    let model: DiffViewerModel
    /// How far the card has folded, from 0 to 1; its height shrinks from the whole card to the header alone.
    var foldProgress: CGFloat = 0

    func makeCoordinator() -> CardHosts {
        CardHosts(card: self)
    }

    func makeNSView(context: Context) -> StickyCardView {
        let hosts = context.coordinator
        let view = StickyCardView(header: hosts.header.view, body: hosts.body.view)
        view.stickyGap = CombinedDiffView.topInset
        view.onBodyHidden = { [weak hosts] in hosts?.bodyDidHide() }
        return view
    }

    func updateNSView(_ view: StickyCardView, context: Context) {
        view.bodyBackground = model.palette.background
        if context.coordinator.update(to: self) { view.invalidateIntrinsicContentSize() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: StickyCardView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let hosts = context.coordinator
        // No width to lay the panes out at yet: the last height keeps the list's geometry finite meanwhile.
        guard width > 0 else { return hosts.lastHeight.map { CGSize(width: 0, height: $0) } }
        let heights = hosts.heights(forWidth: width)
        view.headerHeight = heights.header
        view.bodyHeight = heights.body
        return CGSize(
            width: width,
            height: StickyCardGeometry.cardHeight(
                headerHeight: heights.header, bodyHeight: heights.body, foldProgress: foldProgress))
    }
}

/// A card's header and body heights at one width.
private struct CardHeights: Equatable {
    let header: CGFloat
    /// The body's own height; zero while it is unmounted. A card folding still reports it, for the body to keep.
    let body: CGFloat
}

/// A card's two hosting controllers and its text systems, which it builds once per render. A folded card holds no
/// panes, but its body goes only once the fold has clipped it away: see ``CardBodyMount``.
private final class CardHosts {
    let header: NSHostingController<FileCardHeader>
    let body: NSHostingController<FileCardBody>
    private var card: StickyCard
    private var layouts: CardLayouts?
    private var width: CGFloat = 0
    private var mount = CardBodyMount<BodyInputs>()
    private var measured: (key: MeasureKey, heights: CardHeights)?

    /// What the body is built from; the body is rebuilt only when these change.
    private struct BodyInputs: Equatable {
        let renderID: RenderedDiff.ID
        let options: PaneOptions
        let width: CGFloat
    }

    private struct MeasureKey: Equatable {
        let mounted: BodyInputs?
        let isCollapsed: Bool
        let title: CardTitle
        let width: CGFloat
    }

    private static let log = Logger(subsystem: "fr.gcqd.GitDiffViewer", category: "cards")

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
            || previous.foldProgress != card.foldProgress || previous.options != card.options
            || previous.file.rendered.id != card.file.rendered.id
    }

    /// The card's height when it was last measured, or nil before any width came.
    var lastHeight: CGFloat? {
        measured.map {
            StickyCardGeometry.cardHeight(
                headerHeight: $0.heights.header, bodyHeight: $0.heights.body, foldProgress: card.foldProgress)
        }
    }

    /// The header's and the body's heights at `width`, rounded up to whole points so the seam stays on the pixel
    /// grid; measured again only when `width` or an input changes. Every height is finite and at most
    /// ``StickyCardGeometry/maximumLength``.
    func heights(forWidth width: CGFloat) -> CardHeights {
        if width != self.width {
            self.width = width
            refreshBody()
        }
        let key = MeasureKey(mounted: mount.mounted, isCollapsed: card.isCollapsed, title: card.title, width: width)
        if let measured, measured.key == key { return measured.heights }
        let fitting = CGSize(width: width, height: .greatestFiniteMagnitude)
        let headerHeight = accepted(
            header.sizeThatFits(in: fitting).height, of: "header", fallback: measured?.heights.header ?? 0)
        let bodyHeight =
            mount.mounted == nil
            ? 0 : accepted(body.sizeThatFits(in: fitting).height, of: "body", fallback: measured?.heights.body ?? 0)
        let heights = CardHeights(header: headerHeight, body: bodyHeight)
        measured = (key, heights)
        return heights
    }

    /// Takes the card's report that it shows none of its body, which unmounts a folded card's body.
    func bodyDidHide() {
        apply(mount.bodyHidden(isCollapsed: card.isCollapsed))
    }

    /// A measured length rounded up to a whole point, or, when it is not finite or past
    /// ``StickyCardGeometry/maximumLength``, the length measured last: SwiftUI's scroll view turns such a height into
    /// a NaN offset, which AppKit traps on.
    private func accepted(_ length: CGFloat, of part: String, fallback: CGFloat) -> CGFloat {
        guard StickyCardGeometry.isAcceptable(length) else {
            Self.log.fault("A card's \(part) measured \(Double(length)) for \(self.card.file.path, privacy: .private)")
            assertionFailure("A card's \(part) measured \(length)")
            return StickyCardGeometry.length(length, fallback: fallback)
        }
        return length.rounded(.up)
    }

    /// Follows the card's inputs and fold. The body waits for a width, since its panes lay their text out for it.
    private func refreshBody() {
        let inputs = width > 0 ? BodyInputs(renderID: card.file.rendered.id, options: card.options, width: width) : nil
        apply(mount.update(to: inputs, isCollapsed: card.isCollapsed))
    }

    private func apply(_ change: CardBodyMount<BodyInputs>.Change) {
        switch change {
            case .none:
                break
            case .mount:
                let rendered = card.file.rendered
                let layouts =
                    layouts.flatMap { $0.renderID == rendered.id ? $0 : nil } ?? CardLayouts(rendered: rendered)
                self.layouts = layouts
                body.rootView = FileCardBody(
                    content: PaneContent(layouts: layouts, rendered: rendered, model: card.model), width: width,
                    options: card.options)
            case .unmount:
                body.rootView = FileCardBody(content: nil, width: width, options: card.options)
        }
    }

    private static func header(for card: StickyCard) -> FileCardHeader {
        let model = card.model
        let path = card.file.path
        return FileCardHeader(
            title: card.title, isCollapsed: card.isCollapsed, toggle: { model.toggleCollapsed(path) },
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
            ChangeBadge(summary: title.summary, scheme: title.badgeScheme, state: title.badgeState)
        }
        .padding(.leading, 12)
        // The badge sits as far from the card's edge as from its top and bottom.
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // Opaque, so nothing behind the header needs a blur; the card's clip rounds it.
        .background(ChangeGlyph(title.summary.kind).color(in: title.badgeScheme).opacity(0.08))
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
        switch options.layout {
            case .inline:
                if content.layouts.unified != nil {
                    pane(content, side: .unified, gutter: .dual, width: width)
                }
            case .split:
                if content.layouts.old != nil, content.layouts.new != nil {
                    SideBySidePanes(width: width) { paneWidth in
                        pane(content, side: .old, gutter: .old, width: paneWidth)
                    } trailing: { paneWidth in
                        pane(content, side: .new, gutter: .new, width: paneWidth)
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
