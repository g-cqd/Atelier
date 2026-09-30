package import AemiCore
package import AtelierFileTree
import AtelierLSP
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
    /// Injected after init; nil leaves diagnostics off entirely.
    package var diagnostics: DiagnosticsModel?
    /// Bumped whenever ``diagnostics``' findings change, so a view holding a ``DiffTextKit/DiagnosticOverlay``,
    /// which observation cannot see into, knows to recompute it.
    package internal(set) var diagnosticsVersion = 0
    /// Injected after init; nil leaves hover documentation off entirely.
    package var hoverDocs: HoverDocumentationModel?
    /// Injected after init by ``attachFreshness()``; nil leaves freshness watching off entirely.
    package var freshness: RepositoryFreshness?

    package internal(set) var selectedPath: String?
    package internal(set) var tabs = DiffTabs()
    package private(set) var comparison = Comparison.empty
    package private(set) var trees = ExplorerTrees.empty
    /// Where every path of the unified explorer and the tabs stands against the index, by left-side path: both
    /// sides' ``SideState/badgeStates`` merged, a right-side file under its left-side counterpart.
    package internal(set) var unifiedBadgeStates = BadgeChangeStates.uniform(.staged)
    package internal(set) var folding = CardFolding()
    /// The merged sidebar's grouping by commit, when the setting asks for it (GIT-06).
    package internal(set) var commitGroups = CommitGroupsState.off
    /// The change the selection shows when it is a commit group's own, or a file's under one, rather than the
    /// comparison's (D39); nil for every other selection.
    package internal(set) var commitScope: CommitScope?
    package internal(set) var scrollRequest: ScrollRequest?
    /// The palette for the selected Xcode theme, or the system one when none is selected or it cannot be read.
    /// Read once per theme change: it comes from a property list on disk.
    package private(set) var palette: DiffPalette
    /// Where each open file tab's panes were scrolled, which the panes record as they leave the screen and read back
    /// when their file shows again.
    package let scrollMemory = PaneScrollMemory()
    var timer: OperationTimer
    var navigator = ChangeNavigator()

    let pipeline: RenderPipeline
    /// Runs gap handle drags, revealing rows through ``pipeline`` one card at a time.
    let gapDrags: GapDragController
    private let preparer: DiffPreparer
    /// What one parse of each Swift side learned, shared by the intraline diff, the colour tier and hover, so a side
    /// is parsed once for all three (PERF-11 step 3).
    let syntaxFacts = SyntaxFactsStore()
    /// Which displayed Swift sides take sourcekit-lsp's semantic colour.
    let semanticColor = SemanticColorSource()
    /// Which tiers the refinement runs: grammar colour per language, and Swift's while its setting is on.
    let colorGate = ColorTierGate()
    /// The app's grammar colour, once the window attaches it.
    @ObservationIgnored var attachedGrammarColor: GrammarColorServices?
    let reader: any SourceReading
    /// Spawns the model's work, and its views' work on its behalf, so a test settles on one provider.
    package let taskProvider: any TaskProvider
    @ObservationIgnored private var sourcesTask: Task<Void, Never>?
    @ObservationIgnored private var prologueTask: Task<LoadedSides?, Never>?
    @ObservationIgnored private var renamesTask: Task<Void, Never>?
    @ObservationIgnored private var treesTask: Task<Void, Never>?
    /// Bumped by every ``rebuildTrees()``; a build that lands after a newer one started is dropped.
    @ObservationIgnored private var treesGeneration = 0
    @ObservationIgnored var diagnosticsTask: Task<Void, Never>?
    /// Reads the history the grouping by commit lists; nil leaves the grouping unavailable.
    let history: CommitHistory?
    @ObservationIgnored var commitGroupsTask: Task<Void, Never>?
    /// Bumped by every start or cancellation of a grouping load; a load that finds it moved on drops its result.
    @ObservationIgnored var commitGroupsGeneration = 0
    /// What the last grouping load was asked, so a setting change that asks the same runs nothing.
    @ObservationIgnored var commitGroupsRequest: CommitGroupingEligibility?
    /// The commits the last grouping load listed, reused by the next load of the same range.
    @ObservationIgnored var commitListing: CommitListing?
    @ObservationIgnored var diagnosticsGeneration = 0
    /// ``diagnosticFilePathMaps`` of the pipeline's target at a ``RenderPipeline/targetVersion`` and under a
    /// ``commitScope``'s key, which a pane per card reads on every findings change.
    @ObservationIgnored var diagnosticFilePathCache: (targetVersion: Int, scope: String?, paths: DiagnosticFilePaths)?
    /// How many times ``diagnosticFilePathMaps`` built its maps rather than reading them from its cache.
    @ObservationIgnored package internal(set) var diagnosticFilePathBuilds = 0
    /// Sides whose last listing failed. While one has, the comparison keeps what is published, and
    /// ``shownComparison`` marks it with the failure.
    var failedLoads: Set<Side> = []
    /// Whether ``compareGitChanges(in:leftRef:rightRef:)`` is reading sides other than the ones on screen.
    var isSwitching = false
    /// Why the last ``compareGitChanges(in:leftRef:rightRef:)`` could not open its repository.
    var switchFailure: String?
    /// Whether what is published belongs to a selection the user left while a side was loading: the one they made
    /// waits for the load, and what is on screen until it lands is not what they asked for.
    var showsPreviousSelection = false

    /// Files shown together when a folder or nothing is selected; capped so a whole repository stays responsive.
    package static let combinedFileLimit = 200

    package init(
        settings: ViewerSettings = ViewerSettings(),
        reader: any SourceReading,
        history: CommitHistory? = nil,
        taskProvider: any TaskProvider = .default,
        uptime: @escaping MonotonicNanosecondsProvider = LiveClock.monotonicNanoseconds,
        clock: any Clock<Duration> = ContinuousClock(),
        decorationClock: any Clock<Duration> = ContinuousClock()
    ) {
        self.settings = settings
        self.reader = reader
        self.history = history
        self.taskProvider = taskProvider
        timer = OperationTimer(uptime: { .nanoseconds(uptime()) })
        let palette = Self.palette(for: settings)
        self.palette = palette
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider, store: syntaxFacts)
        self.preparer = preparer
        let pipeline = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: Self.options(settings, palette: palette),
            decorator: DiffDecorator(
                tiers: Self.tiers(store: syntaxFacts, semantic: semanticColor, gate: colorGate),
                clock: decorationClock, store: syntaxFacts))
        self.pipeline = pipeline
        gapDrags = GapDragController(
            taskProvider: taskProvider, clock: clock, expansion: { pipeline.expansion(of: $0) },
            apply: { pipeline.setExpansion($0, for: $1) })
        left = SideState(label: "Left", reader: reader, taskProvider: taskProvider)
        right = SideState(label: "Right", reader: reader, taskProvider: taskProvider)
        left.onReload = { [weak self] in self?.timer.begin() }
        right.onReload = { [weak self] in self?.timer.begin() }
        left.onEntriesChanged = { [weak self] in self?.entriesChanged(on: .left) }
        right.onEntriesChanged = { [weak self] in self?.entriesChanged(on: .right) }
        left.onIgnoredEntriesChanged = { [weak self] in self?.ignoredEntriesChanged() }
        right.onIgnoredEntriesChanged = { [weak self] in self?.ignoredEntriesChanged() }
        left.onBadgeStatesChanged = { [weak self] in self?.updateUnifiedBadgeStates() }
        right.onBadgeStatesChanged = { [weak self] in self?.updateUnifiedBadgeStates() }
        pipeline.configure(
            options: Self.options(settings, palette: palette), context: settings.contextLines,
            isolatesChanges: settings.isolatesChanges)
        pipeline.onEvent = { [weak self] event in self?.handle(event) }
        followColorSettings()
        semanticColor.isEnabled = settings.semanticColor
        semanticColor.readShownRight { [weak self] in
            guard let self else { return (nil, []) }
            return (commitScope?.right ?? right.source, right.entries)
        }
        settings.addObserver(self) { [weak self] change in self?.settingsChanged(change) }
    }

    // MARK: Derived state

    package var statuses: [String: PathStatus] { comparison.statuses }
    /// Renamed files, left path to right path.
    package var renames: [String: String] { comparison.renames.byLeft }
    package var leftTree: [PathNode] { trees.left }
    package var rightTree: [PathNode] { trees.right }
    package var unifiedTree: [PathNode] { trees.unified }
    /// The groups of each explorer: the compared files, and the ignored ones when the setting shows them.
    package var leftSections: [ExplorerSection] { sections(changes: trees.left, ignored: trees.leftIgnored) }
    package var rightSections: [ExplorerSection] { sections(changes: trees.right, ignored: trees.rightIgnored) }
    /// The merged explorer's groups: a section per commit when the grouping by commit has landed, else the plain list.
    package var unifiedSections: [ExplorerSection] {
        guard commitGroups.grouping != nil else {
            return sections(changes: trees.unified, ignored: trees.unifiedIgnored)
        }
        guard settings.showsIgnoredFiles else { return commitGroups.sections }
        return commitGroups.sections + [
            ExplorerSection(kind: .ignored, title: "Ignored Files", nodes: trees.unifiedIgnored)
        ]
    }

    private func sections(changes: [PathNode], ignored: [PathNode]) -> [ExplorerSection] {
        let compared = ExplorerSection(
            kind: .changes, title: settings.showsChangesOnly ? "Changes" : "Files", nodes: changes)
        guard settings.showsIgnoredFiles else { return [compared] }
        return [compared, ExplorerSection(kind: .ignored, title: "Ignored Files", nodes: ignored)]
    }
    /// The repository root the comparison currently belongs to, for the per-project settings identity: the left
    /// side's, else the right's; nil for a patch or for folders outside any repository.
    package var currentProjectRoot: URL? { left.repository?.root ?? right.repository?.root }

    package var rendered: RenderedDiff? { pipeline.file }
    /// One rendered diff per changed file when a folder or nothing is selected.
    package var renderedFiles: [RenderedFile] { pipeline.cards }
    /// The folded cards. A card that stopped folding, such as one a reload found renamed without changes, is not one.
    package var collapsedFiles: Set<String> { folding.collapsed.filter(isFoldable) }
    package var isRendering: Bool { pipeline.isRendering }
    package var renderError: String? { pipeline.error }
    /// What the stages after the text found for `text`, for the pane that shows it; nil until something lands.
    package func decorations(for text: RenderedText?) -> DiffDecorations? {
        text.flatMap { pipeline.decorations(forText: $0.id) }
    }
    /// Where panes report the rows they show, so those are decorated first.
    package var decorationViewport: DecorationViewport { pipeline.decorationViewport }
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
        // A file under a commit group shows on its own, whether or not the comparison lists its path.
        if ExplorerSection.path(inSelection: selectedPath) != nil { return false }
        return !comparison.isFile(selectedPath)
    }

    /// What the detail area shows, derived from the model so the view has no logic of its own. Content already
    /// published outranks a side reload or a render in flight, whatever the selection now asks for: a reload, a
    /// re-comparison or a new diff option keeps the detail views and their scroll position until the replacement
    /// lands, and only a new selection takes them away at once.
    package var detailState: DetailState {
        if isShowingCombinedFiles, !renderedFiles.isEmpty { return .cards }
        if let rendered { return .file(rendered) }
        if !renderedFiles.isEmpty { return .cards }
        if left.isLoading || right.isLoading { return .loading }
        if isRendering { return .loading }
        if let failure = loadFailure ?? renderError { return .error(failure) }
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
        isSwitching = !alreadyCompares(url, leftRef: leftRef, rightRef: rightRef)
        switchFailure = nil
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
                    isSwitching = false
                    switchFailure = "\(Self.displayPath(of: url)) is not inside a git repository."
                    left.endLoading()
                    right.endLoading()
                }
                return
            }
            PhaseTrace.log("prologue done")
            isSwitching = false
            failedLoads = []
            if let listing = loaded.leftListing {
                left.load(
                    loaded.left, repository: loaded.info, listing: listing)
            } else {
                left.load(loaded.left, repository: loaded.info)
            }
            if let listing = loaded.rightListing {
                right.load(
                    loaded.right, repository: loaded.info, listing: listing, badgeStates: loaded.rightBadgeStates)
            } else {
                right.load(loaded.right, repository: loaded.info)
            }
            sourcesChanged()
        }
    }

    /// Shows a unified diff or git patch file: the old side of every file on the left, the new side on the right.
    package func openPatch(_ url: URL) {
        sourcesTask?.cancel()
        prologueTask?.cancel()
        isSwitching = false
        left.load(.patch(url, side: .old), repository: nil)
        right.load(.patch(url, side: .new), repository: nil)
    }

    package func swapSides() {
        sourcesTask?.cancel()
        prologueTask?.cancel()
        isSwitching = false
        let leftSource = left.source
        let leftRepository = left.repository
        if let rightSource = right.source { left.load(rightSource, repository: right.repository) }
        if let leftSource { right.load(leftSource, repository: leftRepository) }
    }

    /// Recomputes the comparison and the trees once both sides are loaded. While a side is still loading, every
    /// file of the other side would look added or deleted, so what is published stays as it is until both have
    /// landed: the comparison, the explorers, the detail area, the findings and the hover corpus. A reload of both
    /// sides always lands one side first, and must not collapse the viewer then.
    package func sourcesChanged() {
        PhaseTrace.log("sourcesChanged")
        offerRepository(from: left, to: right)
        offerRepository(from: right, to: left)
        timer.begin(onlyIfIdle: true)
        preparer.cancelPrefetch()
        renamesTask?.cancel()
        guard !left.isLoading, !right.isLoading, failedLoads.isEmpty else {
            // The watcher still follows the right side's new source, which `load` has already set.
            updateFreshness()
            return
        }
        switchFailure = nil
        comparison = Comparison(
            left: left.entries, right: right.entries, leftSource: left.source, rightSource: right.source,
            leftIgnored: left.ignoredEntries ?? [], rightIgnored: right.ignoredEntries ?? []
        )
        updateUnifiedBadgeStates()
        // No `folding.reset()`: folds are keyed by path, so they survive a reload or re-comparison; `render()` drops
        // those of files the list no longer holds.
        detectRenames()
        rebuildTrees()
        refreshCommitGroups(force: true)
        updateDiagnostics()
        updateFreshness()
        tabs.keepOnly(where: selectionExists)
        retainScrollPositions()
        if let selectedPath, !selectionExists(selectedPath) {
            applySelection(tabs.activePath, keepingPublished: true)
        } else if selectedPath == nil, tabs.tabs.isEmpty, let singleFiles = comparison.singleFiles {
            // Only before any tab is open: with one open, a missing selection is the file list's tab, shown on
            // purpose.
            tabs.open(singleFiles.left)
            applySelection(singleFiles.left, keepingPublished: true)
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
            updateUnifiedBadgeStates()
            rebuildTrees()
            refreshCommitGroups(force: true)
            render()
        }
    }

    /// Applies the changed-files filter and the tree style from the settings to the explorer trees, off the main
    /// actor. Showing the ignored files asks each side for them; they join the comparison when they arrive.
    package func rebuildTrees() {
        treesTask?.cancel()
        treesGeneration += 1
        let generation = treesGeneration
        let comparison = comparison
        let leftTree = left.tree
        let rightTree = right.tree
        let showsChangesOnly = settings.showsChangesOnly
        let showsIgnoredFiles = settings.showsIgnoredFiles
        let style = settings.treeStyle
        treesTask = taskProvider.task {
            let built = await ExplorerTrees.buildOffMain(
                comparison: comparison, leftTree: leftTree, rightTree: rightTree,
                showsChangesOnly: showsChangesOnly, showsIgnoredFiles: showsIgnoredFiles, style: style)
            guard generation == treesGeneration else { return }
            trees = built
            guard settings.showsIgnoredFiles, !left.isLoading, !right.isLoading else { return }
            left.loadIgnoredEntries()
            right.loadIgnoredEntries()
        }
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
    /// A file a commit group's own change shows reads that change's kind.
    package func changeSummary(for leftPath: String, rendered: RenderedDiff?) -> FileChangeSummary {
        FileChangeSummary(
            kind: commitScope?.file(atPath: leftPath)?.summaryKind
                ?? comparison.summaryKind(for: leftPath, directoryStatus: trees.statuses[leftPath]),
            addedLines: rendered?.addedLines ?? 0, removedLines: rendered?.removedLines ?? 0
        )
    }

    // MARK: Cards

    /// Whether `path`'s card folds. A file renamed without changes has no content to fold: its card is its header
    /// alone and never unfolds (DIFF-07).
    package func isFoldable(_ path: String) -> Bool {
        if let file = commitScope?.file(atPath: path) { return !file.isRenameWithoutChanges }
        return !comparison.isRenamedWithoutChanges(path)
    }

    /// The cards of the list that fold, in list order.
    package var foldableFiles: [String] {
        renderedFiles.map(\.path).filter(isFoldable)
    }

    package func toggleCollapsed(_ path: String) {
        guard isFoldable(path) else { return }
        folding.toggle(path)
    }

    package func reloadSources() {
        left.reload()
        right.reload()
    }

    package func setAllCollapsed(_ collapsed: Bool) {
        folding.setAll(foldableFiles, collapsed: collapsed)
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

    /// Feeds a gap handle's drag to ``gapDrags``; each step renders only the card it drags.
    package func handleGapDrag(_ event: GapDragEvent) {
        timer.abandon()
        gapDrags.handle(event)
    }

    package func resetRevealedLines() {
        timer.abandon()
        pipeline.resetGaps()
    }

    package func expansion(of key: GapKey) -> GapExpansion {
        pipeline.expansion(of: key)
    }

    /// Renders the selection. Only a selection the user makes passes `keepingPublished: false`; everything else
    /// (a reload, a re-comparison, a new diff option) keeps what is published on screen until its replacement lands.
    func render(keepingPublished: Bool = true) {
        configurePipeline()
        guard let leftSource = left.source, let rightSource = right.source else {
            setCommitScope(nil)
            pipeline.clear()
            return
        }
        let scope = selectedPath.flatMap(selectionScope(for:))
        setCommitScope(scope)
        // A side still loading, or failed, renders the selection once a load lands; what is published stays until
        // then, marked when the user asked for something else meanwhile.
        guard !left.isLoading, !right.isLoading, failedLoads.isEmpty else {
            if !keepingPublished { showsPreviousSelection = true }
            return
        }
        // A commit's own change, or the working tree's, reads sides of its own (D39).
        if let scope { return render(scope, keepingPublished: keepingPublished) }
        let target: RenderPipeline.Target
        if isShowingCombinedFiles {
            let paths =
                selectedPath.flatMap { commitGroupPaths(forSelection: $0, limit: Self.combinedFileLimit) }
                ?? comparison.changedPaths(under: selectedPath, limit: Self.combinedFileLimit)
            // A fold of a file the list no longer holds would skew the fold count the toolbar reads.
            folding.keepOnly(Set(paths))
            guard !paths.isEmpty else {
                showsPreviousSelection = false
                pipeline.clear()
                timer.finish()
                return
            }
            target = .cards(paths.map(comparison.pair(for:)))
        } else if let selectedPath {
            // A file under Earlier Changes is the comparison's own pair: no listed commit touched it.
            target = .file(comparison.pair(for: ExplorerSection.path(inSelection: selectedPath) ?? selectedPath))
        } else {
            showsPreviousSelection = false
            pipeline.clear()
            timer.finish()
            return
        }
        PhaseTrace.log("render \(target.pairs.count) files")
        pipeline.render(
            target, left: leftSource, right: rightSource, granularity: settings.granularity,
            heuristics: settings.diffHeuristics, keepingPublished: keepingPublished)
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
            sides: settings.mode == .inline ? [.unified] : [.old, .new],
            compactsInline: settings.mode == .inline && settings.compactsInlineView
        )
    }

    /// The palette of the selected Xcode theme, or the system one when none is selected or it cannot be read, with
    /// changes in the chosen diff colours (book D18).
    private static func palette(for settings: ViewerSettings) -> DiffPalette {
        let theme = settings.themePath.flatMap(XcodeThemeLibrary.theme(at:)).map(DiffPalette.init(theme:)) ?? .system
        return theme.with(diffColors: settings.diffColors)
    }

    private func handle(_ event: RenderPipeline.Event) {
        switch event {
            case .published(let id, let isFirst):
                if isFirst {
                    timer.awaitDisplay(of: id)
                    showsPreviousSelection = false
                }
                if isShowingCombinedFiles {
                    folding.applyDefaults(to: renderedFiles.map(\.path), status: shownStatus(ofPath:))
                    // With the scroll to the first change off, the file opens at its top (DIFF-08).
                } else if isFirst, settings.scrollsToFirstChange, let rendered, rendered.changeCount > 0,
                    !rendered.keepsScrollPosition, !returnsToRememberedPosition
                {
                    navigator.focusFirst()
                    requestScrollToCurrentChange()
                }
                // A Findings row opened this file: its line wins over the first change.
                if let row = takeFindingReveal() { scrollRequest = ScrollRequest(row: row) }
                updateHoverDocs()
            case .decorated:
                break
            case .finished:
                folding.listCompleted()
                timer.finish()
                prefetch()
                updateHoverDocs()
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
            case .trees:
                rebuildTrees()
                refreshCommitGroups(force: false)
            case .diff: renderSelection()
            case .layout: relayout()
            case .palette:
                palette = Self.palette(for: settings)
                relayout()
            // The explorers' placement is an appearance setting, and grouping applies to the merged sidebar only.
            case .appearance: followAppearanceSettingsChange()
            // DiagnosticsModel observes ViewerSettings on its own; nothing for this model to do here.
            case .diagnostics: break
            case .freshness: freshness?.setEnabled(settings.autoRefresh)
        }
    }

    // MARK: Timing

    /// Records that a pane put the render with `id` on screen. Panes call this from their update pass, inside
    /// SwiftUI's own observation tracking: touching the timer there, even to check the id, registers a mutation of
    /// a value the same pass depends on, which SwiftUI reports as a graph cycle and then crashes on. Everything
    /// waits for the next turn of the run loop.
    package func noteDisplayed(_ id: RenderedDiff.ID) {
        taskProvider.task {
            pipeline.decorateDisplayed(id)
            guard let elapsed = timer.displayed(id) else { return }
            PhaseTrace.log("displayed")
            timer.record(firstDisplay: elapsed)
        }
    }
}
