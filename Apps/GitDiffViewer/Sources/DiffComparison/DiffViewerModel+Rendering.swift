import AemiCore
import AtelierFileTree
import AtelierLSP
package import DiffCore
import DiffGit
package import DiffRendering
import Foundation
import Observation

import enum AemiRuntime.LiveClock
import typealias AemiRuntime.MonotonicNanosecondsProvider

// Rendering the selection, the pipeline's events, settings changes and display timing; apart from the type's file, to keep it within the limits SwiftLint sets.
extension DiffViewerModel {
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
            target,
            left: leftSource,
            right: rightSource,
            granularity: settings.granularity,
            heuristics: settings.diffHeuristics,
            keepingPublished: keepingPublished
        )
    }

    func configurePipeline() {
        pipeline.configure(
            options: Self.options(settings, palette: palette),
            context: settings.contextLines,
            isolatesChanges: settings.isolatesChanges
        )
    }

    static func options(_ settings: ViewerSettings, palette: DiffPalette) -> DiffRenderer.Options {
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
    static func palette(for settings: ViewerSettings) -> DiffPalette {
        let theme = settings.themePath.flatMap(XcodeThemeLibrary.theme(at:)).map(DiffPalette.init(theme:)) ?? .system
        return theme.with(diffColors: settings.diffColors)
    }

    func handle(_ event: RenderPipeline.Event) {
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
    func prefetch() {
        guard let leftSource = left.source, let rightSource = right.source, !left.isLoading, !right.isLoading else {
            return
        }
        let pairs = comparison.changedPaths(under: nil, limit: Self.combinedFileLimit).map(comparison.pair(for:))
        preparer.prefetch(
            pairs,
            left: leftSource,
            right: rightSource,
            granularity: settings.granularity,
            heuristics: settings.diffHeuristics
        )
    }

    // MARK: Settings

    func settingsChanged(_ change: ViewerSettings.Change) {
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
