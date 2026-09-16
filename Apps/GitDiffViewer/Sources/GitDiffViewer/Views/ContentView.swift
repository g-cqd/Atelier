import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

struct ContentView: View {
    @Bindable var settings: ViewerSettings
    let model: DiffViewerModel
    @Environment(\.openWindow) private var openWindow
    // Owned here so a fold survives a change of placement.
    @State private var leftExplorer = ExplorerUIState()
    @State private var rightExplorer = ExplorerUIState()
    @State private var unifiedExplorer = ExplorerUIState()

    var body: some View {
        VStack(spacing: 0) {
            // One split view for every placement, so the window toolbar is never rebuilt on a placement switch.
            // The sidebar placements get the system sidebar: glass column, toolbar toggle, collapse on narrow windows.
            NavigationSplitView(columnVisibility: columnVisibility) {
                sidebar
                    .ignoresSafeArea(.container, edges: .top)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 340)
                    .toolbar(removing: settings.explorerPlacement == .top ? .sidebarToggle : nil)
            } detail: {
                detail
                    .toolbar(id: ToolbarID.toolbar) { toolbar }
            }
            // Stacked, not inset: scroll views end above the bar instead of running beneath it.
            if settings.showsStatusBar {
                Divider()
                StatusBarView(model: model)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: PatchOpenPanel.isPatch) else { return false }
            model.openPatch(url)
            return true
        }
        .onAppear { PhaseTrace.log("window content appeared") }
        .background { shortcuts }
    }

    /// The top placement keeps the column hidden; the others persist what the user chose.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { settings.explorerPlacement == .top ? .detailOnly : settings.sidebarVisibility.columnVisibility },
            set: { visibility in
                guard settings.explorerPlacement != .top else { return }
                let stored = SidebarVisibility(visibility)
                if settings.sidebarVisibility != stored { settings.sidebarVisibility = stored }
            }
        )
    }

    @ViewBuilder private var sidebar: some View {
        switch settings.explorerPlacement {
            case .top:
                Color.clear
            case .sidebar:
                VSplitView {
                    leftExplorerView(isSidebar: true)
                        .frame(minHeight: 120)
                    rightExplorerView(isSidebar: true)
                        .frame(minHeight: 120)
                }
            case .unifiedSidebar:
                UnifiedExplorerView(model: model, uiState: unifiedExplorer)
        }
    }

    @ViewBuilder private var detail: some View {
        switch settings.explorerPlacement {
            case .top:
                VSplitView {
                    HStack(spacing: 0) {
                        leftExplorerView(isSidebar: false)
                            .frame(maxWidth: .infinity)
                        Divider()
                        rightExplorerView(isSidebar: false)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 200, idealHeight: 280)
                    DiffDetailView(model: model)
                        .frame(minHeight: 240)
                        .layoutPriority(1)
                }
            case .sidebar, .unifiedSidebar:
                DiffDetailView(model: model)
                    .frame(minWidth: 500)
                    .layoutPriority(1)
        }
    }

    private func leftExplorerView(isSidebar: Bool) -> some View {
        FileExplorerView(side: model.left, model: model, position: .left, isSidebar: isSidebar, uiState: leftExplorer)
    }

    private func rightExplorerView(isSidebar: Bool) -> some View {
        FileExplorerView(
            side: model.right, model: model, position: .right, isSidebar: isSidebar, uiState: rightExplorer)
    }

    /// The window's toolbar, customizable: every item has an identity of its own, so View ▸ Customize Toolbar
    /// lets people choose which ones to show, in what order, and how much space to put between them. The items
    /// shown by default are the ones the app had before; the rest are there for the taking.
    ///
    /// The builder reads no model value of its own on purpose: a change to one would regenerate every item, which
    /// takes a noticeable moment. Items that show live values read them inside their own view instead.
    @ToolbarContentBuilder private var toolbar: some CustomizableToolbarContent {
        openingItems
        sourceItems
        viewItems
        optionItems
    }

    /// What to compare, and reading it again.
    @ToolbarContentBuilder private var openingItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarID.compareRepository, placement: .navigation) {
            Button("Repository", systemImage: "arrow.triangle.branch") {
                model.compareGitChanges(in: URL(filePath: FileManager.default.currentDirectoryPath))
            }
            .help("Compare HEAD with the working tree of the current directory")
        }
        ToolbarItem(id: ToolbarID.openPatch, placement: .navigation) {
            Button("Patch", systemImage: "doc.badge.plus") {
                if let url = PatchOpenPanel.choose() { openWindow(value: LaunchConfiguration.patch(url)) }
            }
            .help("Show a unified diff or git patch file (⌘O, or drop the file on the window)")
        }
        ToolbarItem(id: ToolbarID.reload, placement: .navigation) {
            Button("Reload", systemImage: "arrow.clockwise") { model.reloadSources() }
                .help("Read both sides again")
        }
        .defaultCustomization(.hidden)
    }

    /// The two sides. Separate items, so each gets a capsule of its own around a control of its own height.
    @ToolbarContentBuilder private var sourceItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarID.leftSource, placement: .principal) {
            SourceToolbarControl(side: model.left, position: .left).toolbarItemPadding()
        }
        // One is enough to offer a fixed space in the customization sheet, from which people can add as many
        // copies as they want; two declared here would share an identity and crash as a saved one is restored.
        ToolbarSpacer(.fixed, placement: .principal)
        ToolbarItem(id: ToolbarID.swapSides, placement: .principal) {
            Button("Swap sides", systemImage: "arrow.left.arrow.right") { model.swapSides() }
                .help("Swap the two sides")
        }
        ToolbarItem(id: ToolbarID.rightSource, placement: .principal) {
            SourceToolbarControl(side: model.right, position: .right).toolbarItemPadding()
        }
    }

    /// What the diff shows and how to move through it.
    @ToolbarContentBuilder private var viewItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarID.fileStats, placement: .primaryAction) {
            SelectedFileLabel(model: model)
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.totals, placement: .primaryAction) {
            DiffTotalsLabel(model: model)
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.previousChange, placement: .primaryAction) {
            Button("Previous", systemImage: "chevron.up") { model.goToPreviousChange() }
                .help("Previous change (⌘⇧↑)")
        }
        ToolbarItem(id: ToolbarID.nextChange, placement: .primaryAction) {
            Button("Next", systemImage: "chevron.down") { model.goToNextChange() }
                .help("Next change (⌘⇧↓)")
        }
        ToolbarItem(id: ToolbarID.collapseAll, placement: .primaryAction) {
            CollapseAllButton(model: model)
        }
        ToolbarItem(id: ToolbarID.expandAll, placement: .primaryAction) {
            ExpandAllButton(model: model)
        }
        ToolbarItem(id: ToolbarID.layout, placement: .primaryAction) {
            Picker("Layout", selection: $settings.mode) {
                Label("Inline", systemImage: "list.bullet").tag(ViewMode.inline)
                Label("Side by side", systemImage: "rectangle.split.2x1").tag(ViewMode.split)
                Label("Stacked", systemImage: "rectangle.split.1x2").tag(ViewMode.stacked)
            }
            .pickerStyle(.segmented)
            .help("⌘1 inline, ⌘2 side by side, ⌘3 stacked")
        }
        ToolbarItem(id: ToolbarID.isolateChanges, placement: .primaryAction) {
            Toggle("Isolate", systemImage: "text.line.first.and.arrowtriangle.forward", isOn: $settings.isolatesChanges)
                .help("Show only the changed regions with context (⌘4)")
        }
    }

    /// Settings people may want at hand rather than in the options menu.
    @ToolbarContentBuilder private var optionItems: some CustomizableToolbarContent {
        ToolbarItem(id: ToolbarID.wrapLines, placement: .primaryAction) {
            Toggle("Wrap", systemImage: "text.word.spacing", isOn: $settings.wrapsLines)
                .help("Wrap lines too long for the pane")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.minimap, placement: .primaryAction) {
            Toggle("Minimap", systemImage: "map", isOn: $settings.showsMinimap)
                .help("Show the minimap next to each pane")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.changedFilesOnly, placement: .primaryAction) {
            Toggle("Changed only", systemImage: "line.3.horizontal.decrease.circle", isOn: $settings.showsChangesOnly)
                .help("Keep only the folders leading to files that differ")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.ignoredFiles, placement: .primaryAction) {
            Toggle("Ignored", systemImage: "eye.slash", isOn: $settings.showsIgnoredFiles)
                .help("List the files git ignores in a section of their own")
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.whitespace, placement: .primaryAction) {
            WhitespaceMenu(settings: settings)
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.granularity, placement: .primaryAction) {
            GranularityMenu(settings: settings)
        }
        .defaultCustomization(.hidden)
        ToolbarItem(id: ToolbarID.viewOptions, placement: .primaryAction) {
            ViewOptionsMenu(settings: settings)
        }
    }

    /// Invisible buttons that carry the layout shortcuts; toolbar items cannot own keyboard shortcuts.
    private var shortcuts: some View {
        Group {
            Button("Inline") { settings.mode = .inline }.keyboardShortcut("1", modifiers: .command)
            Button("Side by side") { settings.mode = .split }.keyboardShortcut("2", modifiers: .command)
            Button("Stacked") { settings.mode = .stacked }.keyboardShortcut("3", modifiers: .command)
            Button("Isolate changes") { settings.isolatesChanges.toggle() }.keyboardShortcut("4", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}

extension SidebarVisibility {
    var columnVisibility: NavigationSplitViewVisibility {
        switch self {
            case .automatic: .automatic
            case .all: .all
            case .detailOnly: .detailOnly
        }
    }

    init(_ visibility: NavigationSplitViewVisibility) {
        self = visibility == .detailOnly ? .detailOnly : visibility == .automatic ? .automatic : .all
    }
}

/// Identities of the toolbar's items, which macOS stores a customization under: renaming one resets where people
/// had put it, so they are spelled out here rather than written at each use.
enum ToolbarID {
    /// The name macOS files the customization under. Bumped when the set of items changes in a way a saved
    /// arrangement cannot survive: a stale one naming items that no longer exist crashes AppKit as it restores it.
    static let toolbar = "main.2"
    static let compareRepository = "compareRepository"
    static let openPatch = "openPatch"
    static let reload = "reload"
    static let leftSource = "leftSource"
    static let swapSides = "swapSides"
    static let rightSource = "rightSource"
    static let previousChange = "previousChange"
    static let nextChange = "nextChange"
    static let collapseAll = "collapseAll"
    static let expandAll = "expandAll"
    static let layout = "layout"
    static let isolateChanges = "isolateChanges"
    static let wrapLines = "wrapLines"
    static let minimap = "minimap"
    static let changedFilesOnly = "changedFilesOnly"
    static let ignoredFiles = "ignoredFiles"
    static let whitespace = "whitespace"
    static let granularity = "granularity"
    static let totals = "totals"
    static let fileStats = "fileStats"
    static let viewOptions = "viewOptions"
}
