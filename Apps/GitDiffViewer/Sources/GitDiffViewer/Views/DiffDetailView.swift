import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The detail area behind a hosting boundary of its own (book PERF-10). Opening a file from the list, or closing its
/// tab, replaces most of what the detail area holds, and a change that large reaching the window's root graph makes
/// SwiftUI build every toolbar item anew: some 35 to 45 ms of each switch went there. In a hosting view of its own the
/// detail area updates in its own graph, and the root, with the toolbar, never sees it.
///
/// The area runs beneath the toolbar as before: it ignores the column's safe area, and its hosting view takes the
/// insets AppKit gives it, so the card list still scrolls under the toolbar and the file panes still start below it.
struct DetailAreaHost: View {
    let model: DiffViewerModel

    var body: some View {
        Boundary(model: model)
            .ignoresSafeArea()
    }

    private struct Boundary: NSViewRepresentable {
        let model: DiffViewerModel

        func makeNSView(context: Context) -> NSHostingView<DiffDetailView> {
            let view = NSHostingView(rootView: DiffDetailView(model: model))
            // SwiftUI sizes it as it sized the detail area; it asks for no size of its own.
            view.sizingOptions = []
            return view
        }

        func updateNSView(_ view: NSHostingView<DiffDetailView>, context: Context) {
            if view.rootView.model !== model { view.rootView = DiffDetailView(model: model) }
        }
    }
}

struct DiffDetailView: View {
    let model: DiffViewerModel

    private var showsTabs: Bool { !model.tabs.tabs.isEmpty }
    /// The tab bar's height as last laid out, which the file panes run beneath (book TAB-09).
    @State private var tabBarHeight: CGFloat = 0
    /// The height of the bars over the top of the file panes, the toolbar's and the tab bar's, as last laid out: the
    /// upper pane of a stacked file runs beneath them, and splits only what they leave with the lower one (DIFF-01).
    @State private var barsHeight: CGFloat = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A bar rather than a row stacked above the content: the card list scrolls beneath the tabs as it does
            // beneath the toolbar, and the system extends its scroll edge effect over them.
            .safeAreaBar(edge: .top, spacing: 0) {
                if showsTabs {
                    TabBarView(model: model)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: { height in
                            tabBarHeight = height
                        }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.detailState {
            case .cards:
                CombinedDiffView(model: model)
                    .updatingMarker(model.shownComparison)
            case .file(let rendered):
                // The panes run beneath the toolbar and the tab bar, as the card list does (book TAB-09). AppKit knows
                // the toolbar but not the tab bar, a SwiftUI bar: each pane beneath it takes its height as safe area of
                // its own, and the system's scroll edge effect covers both. The marker stays below the bars.
                Color.clear
                    .onGeometryChange(for: CGFloat.self) {
                        $0.safeAreaInsets.top
                    } action: { height in
                        barsHeight = height
                    }
                    .overlay {
                        panes(for: rendered, underBars: showsTabs ? tabBarHeight : 0)
                            .ignoresSafeArea(.container, edges: .top)
                    }
                    .updatingMarker(model.shownComparison)
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

    /// The file's panes; `underBars` is the height of the tab bar, which AppKit does not know of, above them.
    @ViewBuilder private func panes(for rendered: RenderedDiff, underBars: CGFloat) -> some View {
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
                        onGapDrag: { model.handleGapDrag($0) },
                        onDisplayed: { model.noteDisplayed(rendered.id) },
                        scrollMemoryPath: model.renderedPath,
                        underBars: underBars
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
                        onGapDrag: { model.handleGapDrag($0) },
                        onDisplayed: { model.noteDisplayed(rendered.id) },
                        scrollMemoryPath: model.renderedPath,
                        underBars: underBars,
                        barsHeight: barsHeight
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
    let onGapDrag: (GapDragEvent) -> Void
    let onDisplayed: () -> Void
    let scrollMemoryPath: String?
    /// The tab bar's height above the panes: both run beneath it side by side, the old one alone stacked.
    let underBars: CGFloat
    /// The height of every bar above the panes, the toolbar's included, which the upper pane alone runs beneath when
    /// stacked.
    let barsHeight: CGFloat

    @State private var controller = SplitPaneController()

    /// The window's own pane ratio, which a drag of the divider writes once it ends (book DIFF-01).
    private var ratio: Binding<Double> {
        let settings = model.settings
        return Binding(get: { settings.paneRatio }, set: { settings.paneRatio = $0 })
    }

    var body: some View {
        ResizablePanes(axis: isStacked ? .vertical : .horizontal, ratio: ratio, covered: isStacked ? barsHeight : 0) {
            DiagnosticDiffTextView(
                model: model, rendered: old, gutter: .old, keepsScrollPosition: keepsScrollPosition,
                wrapsLines: wrapsLines, wrapColumn: wrapColumn, showsMinimap: showsMinimap,
                syncsScrolling: syncsScrolling, scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, onDisplayed: onDisplayed, scrollMemoryPath: scrollMemoryPath,
                underBars: underBars
            )
        } trailing: {
            DiagnosticDiffTextView(
                model: model, rendered: new, gutter: .new, keepsScrollPosition: keepsScrollPosition,
                wrapsLines: wrapsLines, wrapColumn: wrapColumn, showsMinimap: showsMinimap,
                syncsScrolling: syncsScrolling, scrollRequest: scrollRequest, splitController: controller,
                onGapDrag: onGapDrag, onDisplayed: onDisplayed, scrollMemoryPath: scrollMemoryPath,
                underBars: isStacked ? 0 : underBars
            )
        }
        .onAppear { controller.wrapsLines = wrapsLines }
        .onChange(of: isStacked) { controller.wrapsLines = wrapsLines }
    }
}
