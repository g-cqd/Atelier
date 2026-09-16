package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
package import Foundation
import Observation

package import enum AemiRuntime.LiveClock
package import typealias AemiRuntime.MonotonicNanosecondsProvider

/// The window's state: what is compared, what is selected, and what the detail area shows. Composes the pure
/// comparison, the explorer trees, the render pipeline and the small navigation pieces behind one API.
// The window's composition root is one class on purpose: every collaborator below is private to it. It is split
// along the shared-core extraction (git and file-tree state leave it first). Reviewed opt-out; g-cqd.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
package final class DiffViewerModel {
    package let left: SideState
    package let right: SideState
    package let settings: ViewerSettings

    package private(set) var selectedPath: String?
    package private(set) var tabs = DiffTabs()
    package private(set) var comparison = Comparison.empty
    package private(set) var trees = ExplorerTrees.empty
    package private(set) var folding = CardFolding()
    package private(set) var scrollRequest: ScrollRequest?
    /// The palette for the selected Xcode theme, or the system one when none is selected or it cannot be read.
    /// Read once per theme change: it comes from a property list on disk.
    package private(set) var palette: DiffPalette
    private var timer: OperationTimer
    private var navigator = ChangeNavigator()

    private let pipeline: RenderPipeline
    private let preparer: DiffPreparer
    private let reader: any SourceReading
    private let taskProvider: any TaskProvider
    @ObservationIgnored private var sourcesTask: Task<Void, Never>?
    @ObservationIgnored private var prologueTask: Task<LoadedSides?, Never>?
    @ObservationIgnored private var renamesTask: Task<Void, Never>?

    /// Files shown together when a folder or nothing is selected; capped so a whole repository stays responsive.
    package static let combinedFileLimit = 200

    package init(
        settings: ViewerSettings = ViewerSettings(),
        reader: any SourceReading,
        taskProvider: any TaskProvider = .default,
        uptime: @escaping MonotonicNanosecondsProvider = LiveClock.monotonicNanoseconds
    ) {
        self.settings = settings
        self.reader = reader
        self.taskProvider = taskProvider
        timer = OperationTimer(uptime: { .nanoseconds(uptime()) })
        let palette = Self.palette(for: settings.themePath)
        self.palette = palette
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        self.preparer = preparer
        pipeline = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: Self.options(settings, palette: palette))
        left = SideState(label: "Left", reader: reader, taskProvider: taskProvider)
        right = SideState(label: "Right", reader: reader, taskProvider: taskProvider)
        left.onReload = { [weak self] in self?.timer.begin() }
        right.onReload = { [weak self] in self?.timer.begin() }
        left.onEntriesChanged = { [weak self] in self?.sourcesChanged() }
        right.onEntriesChanged = { [weak self] in self?.sourcesChanged() }
        left.onIgnoredEntriesChanged = { [weak self] in self?.ignoredEntriesChanged() }
        right.onIgnoredEntriesChanged = { [weak self] in self?.ignoredEntriesChanged() }
        pipeline.configure(
            options: Self.options(settings, palette: palette), context: settings.contextLines,
            isolatesChanges: settings.isolatesChanges)
        pipeline.onEvent = { [weak self] event in self?.handle(event) }
        settings.addObserver(self) { [weak self] change in self?.settingsChanged(change) }
    }

    // MARK: Derived state

    package var statuses: [String: PathStatus] { comparison.statuses }
    /// Renamed files, left path to right path.
    package var renames: [String: String] { comparison.renames.byLeft }
    package var leftTree: [FileNode] { trees.left }
    package var rightTree: [FileNode] { trees.right }
    package var unifiedTree: [FileNode] { trees.unified }
    /// The groups of each explorer: the compared files, and the ignored ones when the setting shows them.
    package var leftSections: [ExplorerSection] { sections(changes: trees.left, ignored: trees.leftIgnored) }
    package var rightSections: [ExplorerSection] { sections(changes: trees.right, ignored: trees.rightIgnored) }
    package var unifiedSections: [ExplorerSection] { sections(changes: trees.unified, ignored: trees.unifiedIgnored) }

    private func sections(changes: [FileNode], ignored: [FileNode]) -> [ExplorerSection] {
        let compared = ExplorerSection(
            kind: .changes, title: settings.showsChangesOnly ? "Changes" : "Files", nodes: changes)
        guard settings.showsIgnoredFiles else { return [compared] }
        return [compared, ExplorerSection(kind: .ignored, title: "Ignored Files", nodes: ignored)]
    }
    package var rendered: RenderedDiff? { pipeline.file }
    /// One rendered diff per changed file when a folder or nothing is selected.
    package var renderedFiles: [RenderedFile] { pipeline.cards }
    package var collapsedFiles: Set<String> { folding.collapsed }
    package var isRendering: Bool { pipeline.isRendering }
    package var renderError: String? { pipeline.error }
    package var gapExpansions: [GapKey: GapExpansion] { pipeline.gapExpansions }
    /// Files composing the current card list, in render order.
    package var combinedFiles: [String] {
        if case .cards(let pairs) = pipeline.target { pairs.map(\.path) } else { [] }
    }
    /// How long the current operation has taken so far.
    package var timing: RenderTiming { timer.timing }
    package var changedPathCount: Int { comparison.changedPathCount }

    package var changeCount: Int {
        isShowingCombinedFiles ? renderedFiles.count : rendered?.changeCount ?? 0
    }

    package var currentChange: Int? { navigator.current(count: changeCount) }

    /// Whether the selection names a directory or nothing, in which case every changed file underneath is shown.
    package var isShowingCombinedFiles: Bool {
        guard let selectedPath else { return true }
        return !comparison.isFile(selectedPath)
    }

    /// What the detail area shows, derived from the model so the view has no logic of its own.
    package var detailState: DetailState {
        if left.isLoading || right.isLoading { return .loading }
        if isShowingCombinedFiles, !renderedFiles.isEmpty { return .cards }
        if let rendered { return .file(rendered) }
        if isRendering { return .loading }
        if let renderError { return .error(renderError) }
        guard left.source != nil, right.source != nil else { return .noSources }
        return isShowingCombinedFiles ? .noChanges : .noSelection
    }

    // MARK: Startup and sources

    /// Starts the comparison named on the command line. Called from the app's initializer, so the git work runs
    /// while SwiftUI is still building the window.
    package func start(_ launch: LaunchConfiguration) {
        PhaseTrace.log("start")
        switch launch {
            case .patch(let url):
                openPatch(url)
            case .files(let left, let right):
                self.left.choose(left)
                self.right.choose(right)
            case .repository(let url, let leftRef, let rightRef):
                compareGitChanges(in: url, leftRef: leftRef, rightRef: rightRef)
        }
    }

    /// Compares `leftRef` with `rightRef`, or with the working tree when `rightRef` is nil, in the repository
    /// containing `url`. Repository info and both file lists are read off the main actor in one go and applied
    /// together, so the comparison is computed once and the explorers never see one side without the other.
    package func compareGitChanges(in url: URL, leftRef: String = "HEAD", rightRef: String? = nil) {
        timer.begin()
        left.beginLoading()
        right.beginLoading()
        sourcesTask?.cancel()
        prologueTask?.cancel()
        let reader = reader
        // Detached so the git work starts now, not after SwiftUI's first main-actor turn; stored so it is cancelled
        // directly when superseded.
        let prologue = taskProvider.detachedTask(priority: .userInitiated) {
            await Self.loadSides(in: url, leftRef: leftRef, rightRef: rightRef, reader: reader)
        }
        prologueTask = prologue
        sourcesTask = taskProvider.task {
            guard let loaded = await prologue.value, !Task.isCancelled else {
                PhaseTrace.log("prologue failed")
                if !Task.isCancelled {
                    left.endLoading()
                    right.endLoading()
                }
                return
            }
            PhaseTrace.log("prologue done")
            if let entries = loaded.leftEntries {
                left.load(loaded.left, repository: loaded.info, entries: entries)
            } else {
                left.load(loaded.left, repository: loaded.info)
            }
            if let entries = loaded.rightEntries {
                right.load(loaded.right, repository: loaded.info, entries: entries)
            } else {
                right.load(loaded.right, repository: loaded.info)
            }
            sourcesChanged()
        }
    }

    private struct LoadedSides: Sendable {
        let info: RepositoryInfo
        let left: ComparisonSource
        let right: ComparisonSource
        let leftEntries: [SourceEntry]?
        let rightEntries: [SourceEntry]?
    }

    private static func loadSides(in url: URL, leftRef: String, rightRef: String?, reader: any SourceReading) async
        -> LoadedSides?
    {
        guard let info = await reader.repositoryInfo(containing: url) else { return nil }
        let leftSource = ComparisonSource.gitRef(repository: info.root, ref: leftRef)
        let rightSource =
            rightRef.map { ComparisonSource.gitRef(repository: info.root, ref: $0) } ?? .directory(info.root)
        async let leftEntries = reader.entries(of: leftSource)
        async let rightEntries = reader.entries(of: rightSource)
        let loaded = LoadedSides(
            info: info, left: leftSource, right: rightSource, leftEntries: try? await leftEntries,
            rightEntries: try? await rightEntries)
        PhaseTrace.log("prologue loaded")
        return loaded
    }

    /// Shows a unified diff or git patch file: the old side of every file on the left, the new side on the right.
    package func openPatch(_ url: URL) {
        sourcesTask?.cancel()
        prologueTask?.cancel()
        left.load(.patch(url, side: .old), repository: nil)
        right.load(.patch(url, side: .new), repository: nil)
    }

    package func swapSides() {
        sourcesTask?.cancel()
        prologueTask?.cancel()
        let leftSource = left.source
        let leftRepository = left.repository
        if let rightSource = right.source { left.load(rightSource, repository: right.repository) }
        if let leftSource { right.load(leftSource, repository: leftRepository) }
    }

    /// Recomputes the comparison and the trees once both sides are loaded. While a side is still loading, every
    /// file of the other side would look added or deleted, and populating the explorers with that transient state
    /// costs seconds on a large repository; the explorers stay empty until the real statuses are known.
    package func sourcesChanged() {
        PhaseTrace.log("sourcesChanged")
        offerRepository(from: left, to: right)
        offerRepository(from: right, to: left)
        timer.begin(onlyIfIdle: true)
        preparer.cancelPrefetch()
        renamesTask?.cancel()
        guard !left.isLoading, !right.isLoading else {
            comparison = .empty
            trees = .empty
            pipeline.clear()
            return
        }
        comparison = Comparison(
            left: left.entries, right: right.entries, leftSource: left.source, rightSource: right.source,
            leftIgnored: left.ignoredEntries ?? [], rightIgnored: right.ignoredEntries ?? []
        )
        folding.reset()
        detectRenames()
        rebuildTrees()
        tabs.keepOnly { comparison.contains($0) }
        if let selectedPath, !comparison.contains(selectedPath) {
            applySelection(tabs.activePath)
        } else if selectedPath == nil, let singleFiles = comparison.singleFiles {
            tabs.open(singleFiles.left)
            applySelection(singleFiles.left)
        } else {
            render()
        }
    }

    /// A folder chosen for one side while the other side is empty puts that side on the same repository, so its
    /// menu offers the branches to compare the folder with; the comparison waits for that choice.
    private func offerRepository(from side: SideState, to other: SideState) {
        guard other.source == nil, other.repository == nil, case .directory = side.source,
            let repository = side.repository
        else { return }
        other.adopt(repository: repository)
    }

    /// Renames git detects arrive later than the exact ones; they refine the comparison in place without
    /// restarting the render.
    private func detectRenames() {
        guard let leftSource = left.source, let rightSource = right.source else { return }
        let reader = reader
        renamesTask = taskProvider.task {
            let detected = await reader.renames(from: leftSource, to: rightSource)
            guard !detected.isEmpty, !Task.isCancelled, left.source == leftSource, right.source == rightSource else {
                return
            }
            comparison.merge(gitRenames: detected)
            rebuildTrees()
            render()
        }
    }

    /// Applies the changed-files filter and the tree style from the settings to the explorer trees. Showing the
    /// ignored files asks each side for them; they join the comparison when they arrive, without a re-render.
    package func rebuildTrees() {
        trees = ExplorerTrees.build(
            comparison: comparison, leftTree: left.tree, rightTree: right.tree,
            showsChangesOnly: settings.showsChangesOnly, showsIgnoredFiles: settings.showsIgnoredFiles,
            style: settings.treeStyle
        )
        guard settings.showsIgnoredFiles, !left.isLoading, !right.isLoading else { return }
        left.loadIgnoredEntries()
        right.loadIgnoredEntries()
    }

    private func ignoredEntriesChanged() {
        guard !left.isLoading, !right.isLoading else { return }
        comparison.setIgnored(left: left.ignoredEntries ?? [], right: right.ignoredEntries ?? [])
        rebuildTrees()
    }

    // MARK: Statuses and paths

    package func status(of path: String, in side: Side) -> PathStatus? {
        status(ofPath: side == .left ? path : comparison.counterpartPath(of: path, in: .right))
    }

    /// Status of a file or directory by its left-side path.
    package func status(ofPath path: String) -> PathStatus? {
        trees.statuses[path]
    }

    package func counterpartPath(of path: String, in side: Side) -> String {
        comparison.counterpartPath(of: path, in: side)
    }

    package func displayPath(for leftPath: String) -> String {
        comparison.displayPath(for: leftPath)
    }

    package func isRenamedWithChanges(_ leftPath: String) -> Bool {
        comparison.isRenamedWithChanges(leftPath)
    }

    /// The badge for a file, from its status and its rendered line counts when they are known.
    package func changeSummary(for leftPath: String, rendered: RenderedDiff?) -> FileChangeSummary {
        FileChangeSummary(
            kind: comparison.summaryKind(for: leftPath, directoryStatus: trees.statuses[leftPath]),
            addedLines: rendered?.addedLines ?? 0, removedLines: rendered?.removedLines ?? 0
        )
    }

    // MARK: Selection

    /// A single click: shows the file or folder in the temporary tab. Nil closes every tab and shows the whole list.
    package func select(_ path: String?, from side: Side = .left) {
        timer.begin()
        let leftPath = path.map { side == .left ? $0 : comparison.counterpartPath(of: $0, in: .right) }
        if let leftPath { tabs.open(leftPath) } else { tabs.closeAll() }
        applySelection(leftPath)
    }

    /// A double click: shows the file or folder in a pinned tab of its own.
    package func pin(_ path: String, from side: Side = .left) {
        timer.begin()
        let leftPath = side == .left ? path : comparison.counterpartPath(of: path, in: .right)
        tabs.pin(leftPath)
        applySelection(leftPath)
    }

    package func activateTab(_ id: DiffTab.ID) {
        tabs.activate(id)
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath)
    }

    package func pinTab(_ id: DiffTab.ID) {
        tabs.pin(id)
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath)
    }

    package func closeTab(_ id: DiffTab.ID) {
        tabs.close(id)
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath)
    }

    private func applySelection(_ leftPath: String?) {
        selectedPath = leftPath
        navigator.reset()
        folding.reset()
        render()
    }

    // MARK: Cards

    package func toggleCollapsed(_ path: String) {
        folding.toggle(path)
    }

    package func reloadSources() {
        left.reload()
        right.reload()
    }

    package func setAllCollapsed(_ collapsed: Bool) {
        folding.setAll(renderedFiles.map(\.path), collapsed: collapsed)
    }

    // MARK: Rendering

    /// Reloads and re-diffs the selection; call when the diff options change.
    package func renderSelection() {
        timer.begin()
        render()
    }

    /// Re-lays out the current diffs; call when only the layout, palette, or line height changed.
    package func relayout() {
        timer.begin()
        configurePipeline()
        guard !pipeline.prepared.isEmpty else { return render() }
        navigator.reset()
        pipeline.relayout(keepingScroll: false)
    }

    package func adjustGap(_ marker: GapMarker, from base: GapExpansion, byLines delta: Int) {
        timer.abandon()
        pipeline.adjustGap(marker, from: base, byLines: delta)
    }

    package func resetRevealedLines() {
        timer.abandon()
        pipeline.resetGaps()
    }

    package func expansion(of key: GapKey) -> GapExpansion {
        pipeline.expansion(of: key)
    }

    private func render() {
        configurePipeline()
        guard let leftSource = left.source, let rightSource = right.source, !left.isLoading, !right.isLoading else {
            pipeline.clear()
            return
        }
        let target: RenderPipeline.Target
        if isShowingCombinedFiles {
            let paths = comparison.changedPaths(under: selectedPath, limit: Self.combinedFileLimit)
            guard !paths.isEmpty else {
                pipeline.clear()
                timer.finish()
                return
            }
            target = .cards(paths.map(comparison.pair(for:)))
        } else if let selectedPath {
            target = .file(comparison.pair(for: selectedPath))
        } else {
            pipeline.clear()
            timer.finish()
            return
        }
        PhaseTrace.log("render \(target.pairs.count) files")
        pipeline.render(
            target, left: leftSource, right: rightSource, granularity: settings.granularity,
            heuristics: settings.diffHeuristics)
    }

    private func configurePipeline() {
        pipeline.configure(
            options: Self.options(settings, palette: palette), context: settings.contextLines,
            isolatesChanges: settings.isolatesChanges)
    }

    private static func options(_ settings: ViewerSettings, palette: DiffPalette) -> DiffRenderer.Options {
        DiffRenderer.Options(
            granularity: settings.granularity,
            palette: palette,
            lineHeightMultiple: settings.lineHeightMultiple,
            sides: settings.mode == .inline ? [.unified] : [.old, .new]
        )
    }

    private static func palette(for themePath: String?) -> DiffPalette {
        themePath.flatMap(XcodeThemeLibrary.theme(at:)).map(DiffPalette.init(theme:)) ?? .system
    }

    private func handle(_ event: RenderPipeline.Event) {
        switch event {
            case .published(let id, let isFirst):
                if isFirst { timer.awaitDisplay(of: id) }
                if isShowingCombinedFiles {
                    folding.applyDefaults(to: renderedFiles.map(\.path), status: status(ofPath:))
                } else if isFirst, let rendered, rendered.changeCount > 0, !rendered.keepsScrollPosition {
                    navigator.focusFirst()
                    requestScrollToCurrentChange()
                }
            case .finished:
                folding.listCompleted()
                timer.finish()
                prefetch()
            case .failed:
                timer.finish()
        }
    }

    /// Prepares every changed file of the sources in the background, so any later selection is served from the cache.
    private func prefetch() {
        guard let leftSource = left.source, let rightSource = right.source, !left.isLoading, !right.isLoading else {
            return
        }
        let pairs = comparison.changedPaths(under: nil, limit: Self.combinedFileLimit).map(comparison.pair(for:))
        preparer.prefetch(
            pairs, left: leftSource, right: rightSource, granularity: settings.granularity,
            heuristics: settings.diffHeuristics)
    }

    // MARK: Settings

    private func settingsChanged(_ change: ViewerSettings.Change) {
        switch change {
            case .trees: rebuildTrees()
            case .diff: renderSelection()
            case .layout: relayout()
            case .palette:
                palette = Self.palette(for: settings.themePath)
                relayout()
            case .appearance: break
        }
    }

    // MARK: Timing

    /// Records that a pane put the render with `id` on screen. Panes call this from their update pass, inside
    /// SwiftUI's own observation tracking: touching the timer there, even to check the id, registers a mutation of
    /// a value the same pass depends on, which SwiftUI reports as a graph cycle and then crashes on. Everything
    /// waits for the next turn of the run loop.
    package func noteDisplayed(_ id: RenderedDiff.ID) {
        taskProvider.task {
            guard let elapsed = timer.displayed(id) else { return }
            PhaseTrace.log("displayed")
            timer.record(firstDisplay: elapsed)
        }
    }

    // MARK: Change navigation

    package func goToNextChange() {
        navigator.next(count: changeCount)
        requestScrollToCurrentChange()
    }

    package func goToPreviousChange() {
        navigator.previous(count: changeCount)
        requestScrollToCurrentChange()
    }

    /// In a file the request names a row; in a file list it names the file card to bring into view.
    private func requestScrollToCurrentChange() {
        guard let index = navigator.current(count: changeCount).map({ $0 - 1 }) else { return }
        if isShowingCombinedFiles {
            scrollRequest = ScrollRequest(row: index)
            return
        }
        guard let rendered else { return }
        let starts = settings.mode == .inline ? rendered.unifiedChangeStarts : rendered.splitChangeStarts
        guard index < starts.count else { return }
        scrollRequest = ScrollRequest(row: starts[index])
    }
}

/// What a window was asked to compare: from the command line, the welcome window or the recents.
package enum LaunchConfiguration: Hashable, Codable, Sendable {
    case patch(URL)
    case files(left: URL, right: URL)
    case repository(URL, leftRef: String, rightRef: String?)
}
