import Foundation
import KittyApp
public import KittyCodecs
import KittyFileTree
public import KittyRenderer
import KittySearch
import KittyText
public import KittyWidgets
import KittyWorkspace

@MainActor
public func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let scrollStep = scrollLinesPerTick(
        visibleRows: max(1, layout.contentRows), configured: state.config.editor.scrollLines)

    let treeRect = Rect(
        x: layout.activityBarWidth,
        y: layout.contentStartRow,
        width: layout.sidebarWidth,
        height: layout.contentRows
    )
    let editorRect = Rect(
        x: layout.editorStart,
        y: layout.contentStartRow,
        width: layout.editorWidth,
        height: layout.contentRows
    )

    if state.contextMenu != nil {
        if mouse.kind == .release {
            return
        }

        if mouse.kind == .press, mouse.button == .left,
            let itemIndex = contextMenuItemIndex(
                at: mouse, state: state, columns: pipeline.columns, rows: pipeline.rows)
        {
            state.performContextMenuSelection(at: itemIndex)
            return
        }

        if isWithinContextMenu(mouse, state: state, columns: pipeline.columns, rows: pipeline.rows)
        {
            return
        }

        state.dismissContextMenu()
        if mouse.button != .right || mouse.kind != .press {
            return
        }
    }

    if !mouse.button.isScroll, mouse.kind != .drag {
        cancelPendingAcceleratedScroll(state: state, resetBurst: true)
    }

    if mouse.kind == .release {
        state.scrollDragState = nil
        state.isScrolling = false
        return
    }

    if mouse.kind == .drag, mouse.button == .left, let dragState = state.scrollDragState {
        updateScrollDrag(
            mouse: mouse,
            dragState: dragState,
            treeRect: treeRect,
            editorRect: editorRect,
            state: state
        )
        return
    }

    if mouse.kind == .drag, mouse.button == .left, state.scrollDragState == nil,
        state.selection != nil
    {
        handleSelectionDrag(mouse: mouse, editorRect: editorRect, layout: layout, state: state)
        return
    }

    if mouse.button.isScroll {
        state.scrollDragState = nil
        let now = ContinuousClock.now
        let momentumBlockInterval = Duration.milliseconds(
            max(0, state.config.editor.scrollMomentumBlockMilliseconds))
        let isVerticalWheel = mouse.button == .scrollUp || mouse.button == .scrollDown
        let isHorizontalEditorWheel =
            mouse.col - 1 >= layout.editorStart && !state.config.editor.wrapLines
            && (mouse.button == .scrollLeft || mouse.button == .scrollRight
                || (mouse.modifiers.contains(.shift) && isVerticalWheel))
        let isTabRibbonWheel =
            layout.showTabRibbon && mouse.row == layout.contentStartRow
            && mouse.col - 1 >= layout.editorStart
        let isTreeVerticalWheel =
            !isTabRibbonWheel && mouse.col - 1 < layout.editorStart && isVerticalWheel
        let isEditorVerticalWheel =
            !isTabRibbonWheel && !isTreeVerticalWheel && !isHorizontalEditorWheel && isVerticalWheel
        let handlesVerticalMomentum = isTreeVerticalWheel || isEditorVerticalWheel

        if handlesVerticalMomentum,
            shouldCancelPendingAcceleratedScroll(for: mouse.button, state: state)
        {
            cancelPendingAcceleratedScroll(state: state, resetBurst: true)
        }

        if handlesVerticalMomentum {
            if let blockedDirection = state.blockedMomentumDirection,
                let deadline = state.blockedMomentumDeadline {
                if now < deadline, mouse.button == blockedDirection {
                    state.blockedMomentumDirection = nil
                    state.blockedMomentumDeadline = nil
                    state.isScrolling = false
                    return
                }

                if now >= deadline {
                    state.blockedMomentumDirection = nil
                    state.blockedMomentumDeadline = nil
                }
            }
        }

        // Scroll wheel on tab ribbon row
        if isTabRibbonWheel {
            state.isScrolling = scrollTabRibbon(direction: mouse.button, state: state)
            return
        }

        if isTreeVerticalWheel {
            let didScroll = scrollVertically(
                target: .tree,
                direction: mouse.button,
                scrollStep: scrollStep,
                state: state,
                at: now
            )
            state.isScrolling = didScroll
            if didScroll {
                updateMomentumTracking(
                    afterAcceptedVerticalScroll: mouse.button,
                    at: now,
                    momentumBlockInterval: momentumBlockInterval,
                    state: state
                )
            }
        } else if isHorizontalEditorWheel {
            let hStep = state.config.editor.scrollHorizontalStep
            if mouse.button == .scrollUp || mouse.button == .scrollLeft {
                state.isScrolling = scrollEditorHorizontally(
                    state: state, editorRect: editorRect, delta: -hStep)
            } else if mouse.button == .scrollDown || mouse.button == .scrollRight {
                state.isScrolling = scrollEditorHorizontally(
                    state: state, editorRect: editorRect, delta: hStep)
            }
        } else if isEditorVerticalWheel {
            let didScroll = scrollVertically(
                target: .editor,
                direction: mouse.button,
                scrollStep: scrollStep,
                state: state,
                at: now
            )
            state.isScrolling = didScroll
            if didScroll {
                updateMomentumTracking(
                    afterAcceptedVerticalScroll: mouse.button,
                    at: now,
                    momentumBlockInterval: momentumBlockInterval,
                    state: state
                )
            }
        } else {
            state.isScrolling = false
        }
        return
    }

    guard mouse.kind == .press else { return }
    guard mouse.button == .left || mouse.button == .right else { return }
    let isRightClick = mouse.button == .right

    let now = ContinuousClock.now
    let isDoubleClick = !isRightClick && isWithinDoubleClickThreshold(now: now, last: state.lastClickTime)

    // Tab ribbon click (mouse coords are 1-based, tab ribbon row uses layout.contentStartRow)
    if layout.showTabRibbon && mouse.row == layout.contentStartRow
        && mouse.col - 1 >= layout.editorStart
    {
        guard !isRightClick else { return }
        let tabs = state.tabRibbonTabs()
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: state.bufferManager.activeIndex,
            scrollOffset: state.tabScrollOffset
        )
        if let tabIdx = ribbon.tabIndex(
            atColumn: mouse.col - 1,
            ribbonX: layout.editorStart,
            ribbonWidth: layout.editorWidth
        ) {
            if isDoubleClick && tabIdx == state.bufferManager.activeIndex,
                let buf = state.bufferManager.activeBuffer, buf.isPreview
            {
                buf.isPreview = false
            } else {
                state.switchToTab(tabIdx)
            }
            state.mode = .editor
        }
        state.lastClickTime = now
        return
    }

    // Activity bar click
    if state.config.activityBar.show && mouse.col - 1 < layout.activityBarWidth
        && mouse.row - 1 >= layout.contentStartRow
    {
        guard !isRightClick else { return }
        let items = state.config.activityBar.items
        let relativeRow = mouse.row - 1 - layout.contentStartRow
        if relativeRow >= 0, relativeRow < items.count {
            switch items[relativeRow] {
            case "explorer":
                state.activeSidebarPanel = .explorer
            case "openDocuments":
                state.activeSidebarPanel = .openDocuments
            case "search":
                state.activeSidebarPanel = .search
                if state.inFileSearch == nil {
                    openInFileSearch(state: state)
                }
                state.mode = .searchPanel
                state.searchPanelSelectedIndex = -1
            default:
                break
            }
            state.sidebarCollapsed = false
        }
        return
    }

    // Open files panel click
    if state.activeSidebarPanel == .openDocuments && !state.sidebarCollapsed
        && mouse.col - 1 >= layout.activityBarWidth && mouse.col - 1 < layout.editorStart - 1
        && mouse.row - 1 >= layout.contentStartRow
    {
        guard !isRightClick else { return }
        let relativeRow = mouse.row - 1 - layout.contentStartRow
        let bufferIdx = state.openFilesScrollOffset + relativeRow
        if bufferIdx >= 0, bufferIdx < state.bufferManager.count {
            state.switchToTab(bufferIdx)
            state.openFilesSelectedIndex = bufferIdx
            state.mode = .editor
        }
        return
    }

    // Search panel click
    if state.activeSidebarPanel == .search && !state.sidebarCollapsed
        && mouse.col - 1 >= layout.activityBarWidth && mouse.col - 1 < layout.editorStart - 1
        && mouse.row - 1 >= layout.contentStartRow
    {
        guard !isRightClick else { return }
        let relativeRow = mouse.row - 1 - layout.contentStartRow
        let relativeCol = mouse.col - 1 - layout.activityBarWidth

        if relativeRow <= 1 {
            // Click on header or query field → focus query field
            state.mode = .searchPanel
            state.searchPanelFocus = .findField
            state.searchPanelSelectedIndex = -1
        } else {
            // Calculate the toggle row offset (depends on whether replace field is showing)
            let replaceOffset = state.inFileSearch?.showReplace == true ? 1 : 0
            let toggleRow = 2 + replaceOffset
            let resultsStartRow = 4 + replaceOffset

            if relativeRow == 1 + replaceOffset
                && state.inFileSearch?.showReplace == true
            {
                // Click on replace field
                state.mode = .searchPanel
                state.searchPanelFocus = .replaceField
            } else if relativeRow == toggleRow {
                // Click on toggle indicators
                if relativeCol >= 1 && relativeCol < 5 {
                    // [Aa] toggle
                    state.inFileSearch?.isCaseSensitive.toggle()
                    if var search = state.inFileSearch {
                        executeSearch(&search, lines: state.fileContent)
                        state.inFileSearch = search
                    }
                    if state.searchTarget == .workspace {
                        triggerWorkspaceSearchDebounced(state: state)
                    }
                } else if relativeCol >= 6 && relativeCol < 10 {
                    // [.*] toggle
                    state.inFileSearch?.isRegex.toggle()
                    if var search = state.inFileSearch {
                        executeSearch(&search, lines: state.fileContent)
                        state.inFileSearch = search
                    }
                    if state.searchTarget == .workspace {
                        triggerWorkspaceSearchDebounced(state: state)
                    }
                } else if relativeCol >= 11 && relativeCol < 15 {
                    // [WS]/[F] scope toggle
                    state.searchTarget =
                        state.searchTarget == .currentFile ? .workspace : .currentFile
                    if state.searchTarget == .workspace {
                        triggerWorkspaceSearch(state: state)
                    }
                }
                state.mode = .searchPanel
            } else if relativeRow >= resultsStartRow {
                if state.searchTarget == .currentFile {
                    if let search = state.inFileSearch {
                        let resultIndex = state.searchPanelScrollOffset
                            + (relativeRow - resultsStartRow)
                        if resultIndex >= 0, resultIndex < search.matches.count {
                            state.searchPanelSelectedIndex = resultIndex
                            state.inFileSearch?.activeMatchIndex = resultIndex
                            let match = search.matches[resultIndex]
                            state.cursorRow = match.row
                            state.cursorCol = match.colStart
                            state.mode = .editor
                        }
                    }
                } else {
                    let flatIdx = state.searchPanelScrollOffset
                        + (relativeRow - resultsStartRow)
                    if let (filePath, match) = workspaceFlatResult(at: flatIdx, state: state) {
                        openWorkspaceSearchResult(
                            filePath: filePath, match: match, state: state, pipeline: pipeline)
                    }
                }
            }
        }
        return
    }

    if !isRightClick,
        beginScrollDragIfNeeded(
            mouse: mouse, treeRect: treeRect, editorRect: editorRect, state: state)
    {
        return
    }

    state.isScrolling = false
    let contentRow = mouse.row - 1 - layout.contentStartRow

    let clickRegion = state.focusMap?.hitTest(row: mouse.row - 1, col: mouse.col - 1)
    if clickRegion == .sidebar && contentRow >= 0 {
        if isRightClick {
            state.showTreeContextMenu(at: state.treeScrollOffset + contentRow)
        } else {
            handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
        }
    } else if clickRegion == .editor && contentRow >= 0 {
        if isRightClick {
            state.mode = .editor
            state.showEditorContextMenu()
        } else {
            handleEditorClick(
                mouseRow: mouse.row, mouseCol: mouse.col, editorRect: editorRect, state: state)
        }
    } else if clickRegion == nil && contentRow >= 0 {
        // Fallback: manual rect check when FocusMap is not available
        if mouse.col - 1 >= layout.activityBarWidth && mouse.col - 1 < layout.editorStart - 1 {
            if isRightClick {
                state.showTreeContextMenu(at: state.treeScrollOffset + contentRow)
            } else {
                handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
            }
        } else if mouse.col - 1 >= layout.editorStart {
            if isRightClick {
                state.mode = .editor
                state.showEditorContextMenu()
            } else {
                handleEditorClick(
                    mouseRow: mouse.row, mouseCol: mouse.col, editorRect: editorRect, state: state)
            }
        }
    }

    if !isRightClick {
        state.lastClickTime = now
    }
}

@MainActor
private func shouldCancelPendingAcceleratedScroll(for direction: MouseButton, state: EditorState)
    -> Bool
{
    guard direction == .scrollUp || direction == .scrollDown else { return false }
    guard state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil else {
        return false
    }

    let pendingDirection: MouseButton? =
        if state.pendingAcceleratedScrollLines > 0 {
            .scrollDown
        } else if state.pendingAcceleratedScrollLines < 0 {
            .scrollUp
        } else {
            state.scrollAccelerationDirection
        }

    guard let pendingDirection else { return false }
    return pendingDirection != direction
}

@MainActor
private func updateMomentumTracking(
    afterAcceptedVerticalScroll direction: MouseButton,
    at now: ContinuousClock.Instant,
    momentumBlockInterval: Duration,
    state: EditorState
) {
    let previousDirection = state.lastScrollDirection
    if let previousDirection, previousDirection.isScroll, previousDirection != direction,
        momentumBlockInterval > .zero
    {
        // After a reversal, ignore at most one immediate rebound event from the old direction.
        state.blockedMomentumDirection = previousDirection
        state.blockedMomentumDeadline = now.advanced(by: momentumBlockInterval)
    }
    state.lastScrollDirection = direction
}

@MainActor
private func scrollVertically(
    target: EditorState.AcceleratedScrollTarget,
    direction: MouseButton,
    scrollStep: Int,
    state: EditorState,
    at now: ContinuousClock.Instant
) -> Bool {
    let unitDelta = direction == .scrollUp ? -scrollStep : scrollStep
    let directionChanged =
        state.scrollAccelerationDirection != nil && state.scrollAccelerationDirection != direction
    if directionChanged {
        cancelPendingAcceleratedScroll(state: state, resetBurst: false)
    }

    guard applyVerticalScrollDelta(unitDelta, target: target, state: state) else {
        cancelPendingAcceleratedScroll(state: state, resetBurst: true)
        return false
    }

    let extraLines = extraAcceleratedScrollLines(
        for: direction,
        target: target,
        scrollStep: scrollStep,
        state: state,
        at: now
    )
    guard extraLines > 0 else { return true }
    enqueueAcceleratedScroll(
        lineDelta: direction == .scrollUp ? -extraLines : extraLines, target: target, state: state)
    return true
}

@MainActor
private func applyVerticalScrollDelta(
    _ delta: Int,
    target: EditorState.AcceleratedScrollTarget,
    state: EditorState
) -> Bool {
    switch target {
    case .tree:
        let nextOffset = min(
            max(0, state.cachedFlatTree.count - 1),
            max(0, state.treeScrollOffset + delta)
        )
        guard nextOffset != state.treeScrollOffset else { return false }
        state.treeScrollOffset = nextOffset
    case .editor:
        if state.config.editor.wrapLines {
            guard applyWrapModeScrollDelta(delta, state: state) else { return false }
        } else {
            let nextOffset = min(
                max(0, state.fileLineCount - 1),
                max(0, state.scrollOffset + delta)
            )
            guard nextOffset != state.scrollOffset else { return false }
            state.scrollOffset = nextOffset
        }
    }
    return true
}

@MainActor
private func applyWrapModeScrollDelta(_ delta: Int, state: EditorState) -> Bool {
    let oldLine = state.scrollOffset
    let oldWrapRow = state.wrapRowOffset
    var lineIndex = oldLine
    var wrapRow = oldWrapRow

    let contentWidth = wrapModeContentWidth(state: state)
    state.buildWrapCache(contentWidth: contentWidth)

    if delta > 0 {
        for _ in 0..<delta {
            let lineCount =
                state.wrapCache.lineWrapCounts.indices.contains(lineIndex)
                ? state.wrapCache.lineWrapCounts[lineIndex]
                : 1
            wrapRow += 1
            if wrapRow >= lineCount {
                if lineIndex >= state.fileLineCount - 1 {
                    wrapRow = max(0, lineCount - 1)
                    break
                }
                lineIndex += 1
                wrapRow = 0
            }
        }
    } else {
        for _ in 0..<(-delta) {
            wrapRow -= 1
            if wrapRow < 0 {
                if lineIndex <= 0 {
                    wrapRow = 0
                    break
                }
                lineIndex -= 1
                wrapRow =
                    (state.wrapCache.lineWrapCounts.indices.contains(lineIndex)
                        ? state.wrapCache.lineWrapCounts[lineIndex]
                        : 1) - 1
            }
        }
    }

    guard lineIndex != oldLine || wrapRow != oldWrapRow else { return false }
    state.scrollOffset = lineIndex
    state.wrapRowOffset = wrapRow
    return true
}

@MainActor
private func wrapModeContentWidth(state: EditorState) -> Int {
    state.resolvedWrapContentWidth(
        columns: max(1, state.lastRenderColumns),
        rows: max(2, state.lastRenderRows)
    )
}

@MainActor
private func extraAcceleratedScrollLines(
    for direction: MouseButton,
    target: EditorState.AcceleratedScrollTarget,
    scrollStep: Int,
    state: EditorState,
    at now: ContinuousClock.Instant
) -> Int {
    let config = state.config.editor
    guard config.scrollAccelerationEnabled, scrollStep == 1 else {
        resetScrollAccelerationBurst(state: state)
        return 0
    }

    let window = Duration.milliseconds(max(0, config.scrollAccelerationWindowMilliseconds))
    if state.scrollAccelerationDirection == direction,
        state.scrollAccelerationTarget == target,
        window > .zero,
        let last = state.scrollAccelerationLastEventAt,
        last.duration(to: now) <= window
    {
        state.scrollAccelerationBurstCount += 1
    } else {
        state.scrollAccelerationDirection = direction
        state.scrollAccelerationTarget = target
        state.scrollAccelerationBurstCount = 1
    }
    state.scrollAccelerationLastEventAt = now

    let maxExtraLines = max(0, config.scrollAccelerationMaxExtraLines)
    return min(maxExtraLines, max(0, (state.scrollAccelerationBurstCount - 1) * 2))
}

@MainActor
private func enqueueAcceleratedScroll(
    lineDelta: Int,
    target: EditorState.AcceleratedScrollTarget,
    state: EditorState
) {
    guard lineDelta != 0 else { return }

    if state.pendingAcceleratedScrollTarget != target
        || (state.pendingAcceleratedScrollLines != 0
            && state.pendingAcceleratedScrollLines.signum() != lineDelta.signum())
    {
        cancelPendingAcceleratedScroll(state: state, resetBurst: false)
    }

    state.pendingAcceleratedScrollTarget = target
    state.pendingAcceleratedScrollLines += lineDelta

    guard state.scrollAccelerationTask == nil else { return }

    // Use Task.detached so the loop runs on a background executor.
    // Only the MainActor.run block hops to the main actor, avoiding
    // starvation when other @MainActor work is scheduled concurrently.
    //
    // Audit A13 — snapshot the interval once at task start. The
    // user's `scrollAccelerationStepIntervalMilliseconds` doesn't
    // change mid-acceleration; reading it every tick added an extra
    // MainActor round-trip per ~16 ms cycle. Halving the actor-hop
    // count keeps the scroll loop tight when other UI work is
    // already contending for the main actor.
    let intervalMilliseconds = max(
        1, state.config.editor.scrollAccelerationStepIntervalMilliseconds)
    state.scrollAccelerationTask = Task.detached { [weak state] in
        guard let state else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(intervalMilliseconds))

            let shouldContinue = await MainActor.run { () -> Bool in
                guard state.config.editor.scrollAccelerationEnabled else {
                    cancelPendingAcceleratedScroll(state: state, resetBurst: false)
                    return false
                }
                guard !Task.isCancelled,
                    let resumedTarget = state.pendingAcceleratedScrollTarget,
                    state.pendingAcceleratedScrollLines != 0
                else {
                    state.scrollAccelerationTask = nil
                    return false
                }

                let step = state.pendingAcceleratedScrollLines > 0 ? 1 : -1
                guard applyVerticalScrollDelta(step, target: resumedTarget, state: state) else {
                    cancelPendingAcceleratedScroll(state: state, resetBurst: true)
                    return false
                }
                state.pendingAcceleratedScrollLines -= step
                state.renderRefreshSource?.invalidate()

                if state.pendingAcceleratedScrollLines == 0 {
                    state.pendingAcceleratedScrollTarget = nil
                    state.scrollAccelerationTask = nil
                    return false
                }

                return true
            }

            guard shouldContinue else { return }
        }

        await MainActor.run {
            state.scrollAccelerationTask = nil
        }
    }
}

@MainActor
public func cancelPendingAcceleratedScroll(state: EditorState, resetBurst: Bool) {
    state.scrollAccelerationTask?.cancel()
    state.scrollAccelerationTask = nil
    state.pendingAcceleratedScrollLines = 0
    state.pendingAcceleratedScrollTarget = nil
    if resetBurst {
        resetScrollAccelerationBurst(state: state)
    }
}

/// Synchronously drains all pending accelerated scroll lines, applying each
/// one-by-one. Cancels the background acceleration task first so there is no
/// race.  Intended for deterministic testing.
@MainActor
public func drainPendingAcceleratedScroll(state: EditorState) {
    state.scrollAccelerationTask?.cancel()
    state.scrollAccelerationTask = nil

    guard let target = state.pendingAcceleratedScrollTarget else {
        state.pendingAcceleratedScrollLines = 0
        return
    }

    while state.pendingAcceleratedScrollLines != 0 {
        let step = state.pendingAcceleratedScrollLines > 0 ? 1 : -1
        guard applyVerticalScrollDelta(step, target: target, state: state) else {
            break
        }
        state.pendingAcceleratedScrollLines -= step
    }

    state.pendingAcceleratedScrollLines = 0
    state.pendingAcceleratedScrollTarget = nil
}

@MainActor
private func resetScrollAccelerationBurst(state: EditorState) {
    state.scrollAccelerationDirection = nil
    state.scrollAccelerationTarget = nil
    state.scrollAccelerationBurstCount = 0
    state.scrollAccelerationLastEventAt = nil
}

@MainActor
private func handleTreeClick(contentRow: Int, isDoubleClick: Bool, state: EditorState) {
    let clickIndex = state.treeScrollOffset + contentRow
    guard clickIndex >= 0 && clickIndex < state.cachedFlatTree.count else { return }
    let entry = state.cachedFlatTree[clickIndex].node
    state.noteSelectedPath(entry.path, isDirectory: entry.isDirectory)

    if isDoubleClick && clickIndex == state.lastClickIndex {
        if entry.isDirectory {
            state.toggleExpand(at: clickIndex)
        } else {
            state.openFile(at: clickIndex)
            state.cursorCol = 0
            // Double-click pins the buffer
            if let buf = state.bufferManager.activeBuffer, buf.isPreview {
                buf.isPreview = false
            }
        }
    } else {
        state.selectedTreeIndex = clickIndex
        state.mode = .tree
    }

    state.lastClickIndex = clickIndex
}

@MainActor
private func handleEditorClick(mouseRow: Int, mouseCol: Int, editorRect: Rect, state: EditorState) {
    let editor = makeEditorView(state: state)
    guard
        let position = TextEditorLayout.textPosition(
            for: editor,
            in: editorRect,
            row: mouseRow - 1,
            col: mouseCol - 1
        )
    else {
        return
    }

    state.clearSelection()
    state.selection = TextSelection(anchor: position, head: position)
    state.cursorRow = position.row
    state.cursorCol = position.col
    state.mode = .editor

    let now = ContinuousClock.now
    let isDoubleClick = isWithinDoubleClickThreshold(now: now, last: state.lastClickTime)

    state.lastClickTime = now
    state.lastClickIndex = position.row

    if isDoubleClick {
        handleWordSelection(at: position, state: state)
    }
}

/// 300 ms double-click window matches the previous Date-based behavior.
private let doubleClickThreshold: Duration = .milliseconds(300)

/// Returns `true` when `now` is within the double-click window of `last`.
@inline(__always)
private func isWithinDoubleClickThreshold(
    now: ContinuousClock.Instant,
    last: ContinuousClock.Instant?
) -> Bool {
    guard let last else { return false }
    return last.duration(to: now) < doubleClickThreshold
}

@MainActor
private func handleWordSelection(at pos: TextPosition, state: EditorState) {
    let line = state.fileLine(at: pos.row)
    let chars = Array(line)
    var start = pos.col
    var end = pos.col

    while start > 0 && isWordChar(chars[start - 1]) {
        start -= 1
    }

    while end < chars.count && isWordChar(chars[end]) {
        end += 1
    }

    state.selection = TextSelection(
        anchor: TextPosition(row: pos.row, col: start),
        head: TextPosition(row: pos.row, col: end)
    )
}

@MainActor
private func isWordChar(_ char: Character) -> Bool {
    char.isLetter || char.isNumber || char == "_"
}

@MainActor
private func handleSelectionDrag(
    mouse: MouseEvent, editorRect: Rect, layout: LayoutMetrics, state: EditorState
) {
    let contentTop = layout.contentStartRow
    let contentBottom = layout.contentStartRow + layout.contentRows

    if mouse.row <= contentTop {
        if state.config.editor.wrapLines {
            _ = applyWrapModeScrollDelta(-1, state: state)
        } else {
            state.scrollOffset = max(0, state.scrollOffset - 1)
        }
    } else if mouse.row >= contentBottom {
        if state.config.editor.wrapLines {
            _ = applyWrapModeScrollDelta(1, state: state)
        } else {
            state.scrollOffset = min(state.fileLineCount - 1, state.scrollOffset + 1)
        }
    }

    let editor = makeEditorView(state: state)
    if let pos = TextEditorLayout.textPosition(
        for: editor, in: editorRect, row: mouse.row - 1, col: mouse.col - 1)
    {
        state.selection?.head = pos
        state.cursorRow = pos.row
        state.cursorCol = pos.col
    }
}

@MainActor
private func beginScrollDragIfNeeded(
    mouse: MouseEvent,
    treeRect: Rect,
    editorRect: Rect,
    state: EditorState
) -> Bool {
    // Convert 1-based mouse coords to 0-based screen coords
    let pointerRow = mouse.row - 1
    let pointerCol = mouse.col - 1

    let treeRowCount = state.cachedFlatTree.count
    if let indicatorRect = TreePanelLayout.verticalScrollIndicatorRect(
        rowCount: treeRowCount, in: treeRect),
        pointerCol >= indicatorRect.x,
        pointerCol < indicatorRect.maxX,
        let gripOffset = TreePanelLayout.scrollGripOffset(
            rowCount: treeRowCount,
            scrollOffset: state.treeScrollOffset,
            in: treeRect,
            pointerRow: pointerRow
        )
    {
        state.scrollDragState = EditorState.ScrollDragState(target: .tree, gripOffset: gripOffset)
        state.treeScrollOffset = TreePanelLayout.scrollOffset(
            rowCount: treeRowCount,
            currentOffset: state.treeScrollOffset,
            in: treeRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )
        state.mode = .tree
        state.isScrolling = true
        return true
    }

    let editor = makeEditorView(state: state)
    if let indicatorRect = TextEditorLayout.verticalScrollIndicatorRect(
        for: editor, in: editorRect),
        pointerCol >= indicatorRect.x,
        pointerCol < indicatorRect.maxX,
        let gripOffset = TextEditorLayout.scrollGripOffset(
            for: editor, in: editorRect, pointerRow: pointerRow)
    {
        state.scrollDragState = EditorState.ScrollDragState(target: .editor, gripOffset: gripOffset)
        let pos = TextEditorLayout.scrollPosition(
            for: editor, in: editorRect, pointerRow: pointerRow, gripOffset: gripOffset)
        state.scrollOffset = pos.lineOffset
        state.wrapRowOffset = pos.wrapRowOffset
        state.mode = .editor
        state.isScrolling = true
        return true
    }

    // Check horizontal scroll indicator drag
    if let hRect = TextEditorLayout.horizontalScrollIndicatorRect(
        for: editor, in: editorRect, maxLineWidth: state.maxLineWidth
    ),
        pointerRow >= hRect.y, pointerRow < hRect.maxY,
        pointerCol >= hRect.x, pointerCol < hRect.maxX
    {
        let hMetrics = TextEditorLayout.horizontalScrollMetrics(
            for: editor, in: editorRect, maxLineWidth: state.maxLineWidth
        )
        if let gripOffset = HorizontalScrollIndicatorLayout.gripOffset(
            for: hMetrics, in: hRect, pointerCol: pointerCol
        ) {
            state.scrollDragState = EditorState.ScrollDragState(
                target: .editorHorizontal, gripOffset: gripOffset)
            state.hScrollOffset = HorizontalScrollIndicatorLayout.offset(
                for: hMetrics, in: hRect, pointerCol: pointerCol, gripOffset: gripOffset
            )
            state.mode = .editor
            state.isScrolling = true
            return true
        }
    }

    return false
}

@MainActor
private func updateScrollDrag(
    mouse: MouseEvent,
    dragState: EditorState.ScrollDragState,
    treeRect: Rect,
    editorRect: Rect,
    state: EditorState
) {
    let pointerRow = mouse.row - 1

    switch dragState.target {
    case .tree:
        state.treeScrollOffset = TreePanelLayout.scrollOffset(
            rowCount: state.cachedFlatTree.count,
            currentOffset: state.treeScrollOffset,
            in: treeRect,
            pointerRow: pointerRow,
            gripOffset: dragState.gripOffset
        )
        state.mode = .tree
    case .editor:
        let editor = makeEditorView(state: state)
        let pos = TextEditorLayout.scrollPosition(
            for: editor, in: editorRect, pointerRow: pointerRow, gripOffset: dragState.gripOffset)
        state.scrollOffset = pos.lineOffset
        state.wrapRowOffset = pos.wrapRowOffset
        state.mode = .editor
    case .editorHorizontal:
        let editor = makeEditorView(state: state)
        let pointerCol = mouse.col - 1
        if let hRect = TextEditorLayout.horizontalScrollIndicatorRect(
            for: editor, in: editorRect, maxLineWidth: state.maxLineWidth
        ) {
            let hMetrics = TextEditorLayout.horizontalScrollMetrics(
                for: editor, in: editorRect, maxLineWidth: state.maxLineWidth
            )
            state.hScrollOffset = HorizontalScrollIndicatorLayout.offset(
                for: hMetrics, in: hRect, pointerCol: pointerCol, gripOffset: dragState.gripOffset
            )
        }
        state.mode = .editor
    }

    state.isScrolling = true
}

@MainActor
public func makeEditorView(state: EditorState) -> TextEditor {
    let wrapLayoutCache: TextEditor.WrapLayoutCache?
    if state.config.editor.wrapLines {
        _ = state.resolvedWrapContentWidth(
            columns: max(1, state.lastRenderColumns),
            rows: max(2, state.lastRenderRows)
        )
        wrapLayoutCache = state.wrapLayoutCacheSnapshot()
    } else {
        wrapLayoutCache = nil
    }

    return TextEditor(
        buffer: state.textBuffer,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        wrapRowOffset: state.wrapRowOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        showsGutterDecorations: state.config.git.enabled
            && state.config.git.decorations.showLineChanges
            && state.gitLineDecorationProvider != nil,
        wrapLines: state.config.editor.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.editor.wrapLines,
        maxLineWidth: state.maxLineWidth,
        tabSize: state.config.editor.tabSize,
        wrapLayoutCache: wrapLayoutCache
    )
}

@MainActor
private func scrollTabRibbon(direction: MouseButton, state: EditorState) -> Bool {
    let nextOffset: Int
    if direction == .scrollUp || direction == .scrollLeft {
        nextOffset = max(0, state.tabScrollOffset - 1)
    } else if direction == .scrollDown || direction == .scrollRight {
        nextOffset = min(max(0, state.bufferManager.count - 1), state.tabScrollOffset + 1)
    } else {
        nextOffset = state.tabScrollOffset
    }

    guard nextOffset != state.tabScrollOffset else { return false }
    state.tabScrollOffset = nextOffset
    return true
}

@MainActor
private func scrollEditorHorizontally(state: EditorState, editorRect: Rect, delta: Int) -> Bool {
    let editor = makeEditorView(state: state)
    let metrics = TextEditorLayout.horizontalScrollMetrics(
        for: editor,
        in: editorRect,
        maxLineWidth: state.maxLineWidth
    )
    let nextOffset = min(
        metrics.maxOffset,
        max(0, state.hScrollOffset + delta)
    )
    guard nextOffset != state.hScrollOffset else { return false }
    state.hScrollOffset = nextOffset
    return true
}

@MainActor
public func scrollLinesPerTick(visibleRows: Int, configured: Int?) -> Int {
    if let configured, configured > 0 {
        return configured
    }
    return min(12, max(3, visibleRows / 8))
}
