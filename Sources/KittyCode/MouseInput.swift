import Foundation
import KittyCodecs
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let scrollStep = scrollLinesPerTick(visibleRows: max(1, layout.contentRows), configured: state.config.editor.scrollLines)

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
           let itemIndex = contextMenuItemIndex(at: mouse, state: state, columns: pipeline.columns, rows: pipeline.rows) {
            state.performContextMenuSelection(at: itemIndex)
            return
        }

        if isWithinContextMenu(mouse, state: state, columns: pipeline.columns, rows: pipeline.rows) {
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

    if mouse.kind == .drag, mouse.button == .left, state.scrollDragState == nil, state.selection != nil {
        handleSelectionDrag(mouse: mouse, editorRect: editorRect, layout: layout, state: state)
        return
    }

    if mouse.button.isScroll {
        state.scrollDragState = nil
        let now = Date()
        let momentumBlockInterval = TimeInterval(max(0, state.config.editor.scrollMomentumBlockMilliseconds)) / 1000
        let isVerticalWheel = mouse.button == .scrollUp || mouse.button == .scrollDown
        let isHorizontalEditorWheel = mouse.col - 1 >= layout.editorStart &&
            !state.config.editor.wrapLines &&
            (mouse.button == .scrollLeft || mouse.button == .scrollRight ||
             (mouse.modifiers.contains(.shift) && isVerticalWheel))
        let isTabRibbonWheel = layout.showTabRibbon &&
            mouse.row == layout.contentStartRow &&
            mouse.col - 1 >= layout.editorStart
        let isTreeVerticalWheel = !isTabRibbonWheel &&
            mouse.col - 1 < layout.editorStart &&
            isVerticalWheel
        let isEditorVerticalWheel = !isTabRibbonWheel &&
            !isTreeVerticalWheel &&
            !isHorizontalEditorWheel &&
            isVerticalWheel
        let handlesVerticalMomentum = isTreeVerticalWheel || isEditorVerticalWheel

        if handlesVerticalMomentum, shouldCancelPendingAcceleratedScroll(for: mouse.button, state: state) {
            cancelPendingAcceleratedScroll(state: state, resetBurst: true)
        }

        if handlesVerticalMomentum {
            if let blockedDirection = state.blockedMomentumDirection {
                if now < state.blockedMomentumDeadline, mouse.button == blockedDirection {
                    state.blockedMomentumDirection = nil
                    state.blockedMomentumDeadline = .distantPast
                    state.isScrolling = false
                    return
                }

                if now >= state.blockedMomentumDeadline {
                    state.blockedMomentumDirection = nil
                    state.blockedMomentumDeadline = .distantPast
                }
            }
        }

        // Scroll wheel on tab ribbon row
        if isTabRibbonWheel {
            state.isScrolling = scrollTabRibbon(direction: mouse.button, state: state)
            return
        }

        if isTreeVerticalWheel {
            let didScroll: Bool
            if mouse.button == .scrollUp {
                didScroll = scrollVertically(
                    target: .tree,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            } else {
                didScroll = scrollVertically(
                    target: .tree,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            }
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
                state.isScrolling = scrollEditorHorizontally(state: state, editorRect: editorRect, delta: -hStep)
            } else if mouse.button == .scrollDown || mouse.button == .scrollRight {
                state.isScrolling = scrollEditorHorizontally(state: state, editorRect: editorRect, delta: hStep)
            }
        } else if isEditorVerticalWheel {
            let didScroll: Bool
            if mouse.button == .scrollUp {
                didScroll = scrollVertically(
                    target: .editor,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            } else {
                didScroll = scrollVertically(
                    target: .editor,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            }
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

    let now = Date()
    let isDoubleClick = !isRightClick && now.timeIntervalSince(state.lastClickTime) < 0.3

    // Tab ribbon click (mouse coords are 1-based, tab ribbon row uses layout.contentStartRow)
    if layout.showTabRibbon && mouse.row == layout.contentStartRow && mouse.col - 1 >= layout.editorStart {
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
               let buf = state.bufferManager.activeBuffer, buf.isPreview {
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
    if state.config.activityBar.show && mouse.col - 1 < layout.activityBarWidth && mouse.row - 1 >= layout.contentStartRow {
        guard !isRightClick else { return }
        let items = state.config.activityBar.items
        let relativeRow = mouse.row - 1 - layout.contentStartRow
        if relativeRow >= 0, relativeRow < items.count {
            switch items[relativeRow] {
            case "explorer":
                state.activeSidebarPanel = .explorer
            case "openDocuments":
                state.activeSidebarPanel = .openDocuments
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
       && mouse.row - 1 >= layout.contentStartRow {
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

    if !isRightClick, beginScrollDragIfNeeded(mouse: mouse, treeRect: treeRect, editorRect: editorRect, state: state) {
        return
    }

    state.isScrolling = false
    let contentRow = mouse.row - 1 - layout.contentStartRow

    if mouse.col - 1 >= layout.activityBarWidth && mouse.col - 1 < layout.editorStart - 1 && contentRow >= 0 {
        if isRightClick {
            state.showTreeContextMenu(at: state.treeScrollOffset + contentRow)
        } else {
            handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
        }
    } else if mouse.col - 1 >= layout.editorStart && contentRow >= 0 {
        if isRightClick {
            state.mode = .editor
            state.showEditorContextMenu()
        } else {
            handleEditorClick(mouseRow: mouse.row, mouseCol: mouse.col, editorRect: editorRect, state: state)
        }
    }

    if !isRightClick {
        state.lastClickTime = now
    }
}

@MainActor
private func shouldCancelPendingAcceleratedScroll(for direction: MouseButton, state: EditorState) -> Bool {
    guard direction == .scrollUp || direction == .scrollDown else { return false }
    guard state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil else { return false }

    let pendingDirection: MouseButton? = if state.pendingAcceleratedScrollLines > 0 {
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
    at now: Date,
    momentumBlockInterval: TimeInterval,
    state: EditorState
) {
    let previousDirection = state.lastScrollDirection
    if let previousDirection, previousDirection.isScroll, previousDirection != direction, momentumBlockInterval > 0 {
        // After a reversal, ignore at most one immediate rebound event from the old direction.
        state.blockedMomentumDirection = previousDirection
        state.blockedMomentumDeadline = now.addingTimeInterval(momentumBlockInterval)
    }
    state.lastScrollDirection = direction
}

@MainActor
private func scrollVertically(
    target: EditorState.AcceleratedScrollTarget,
    direction: MouseButton,
    scrollStep: Int,
    state: EditorState,
    at now: Date
) -> Bool {
    let unitDelta = direction == .scrollUp ? -scrollStep : scrollStep
    let directionChanged = state.scrollAccelerationDirection != nil && state.scrollAccelerationDirection != direction
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
    enqueueAcceleratedScroll(lineDelta: direction == .scrollUp ? -extraLines : extraLines, target: target, state: state)
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
            let lineCount = state.wrapCache.lineWrapCounts.indices.contains(lineIndex)
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
                if lineIndex <= 0 { wrapRow = 0; break }
                lineIndex -= 1
                wrapRow = (state.wrapCache.lineWrapCounts.indices.contains(lineIndex)
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
    let layout = LayoutMetrics(
        state: state,
        columns: max(1, state.lastRenderColumns),
        rows: max(2, state.lastRenderRows)
    )
    let lineNumberWidth = max(3, TextDisplayMetrics.lineNumberDigits(forLineCount: state.fileLineCount) + 1)
    let gutterDecoWidth = (state.config.git.enabled && state.config.git.decorations.showLineChanges && state.gitLineDecorationProvider != nil) ? 2 : 0
    let gutterWidth = gutterDecoWidth + lineNumberWidth
    return max(1, layout.editorWidth - gutterWidth - 1)
}

@MainActor
private func extraAcceleratedScrollLines(
    for direction: MouseButton,
    target: EditorState.AcceleratedScrollTarget,
    scrollStep: Int,
    state: EditorState,
    at now: Date
) -> Int {
    let config = state.config.editor
    guard config.scrollAccelerationEnabled, scrollStep == 1 else {
        resetScrollAccelerationBurst(state: state)
        return 0
    }

    let window = TimeInterval(max(0, config.scrollAccelerationWindowMilliseconds)) / 1000
    if state.scrollAccelerationDirection == direction,
       state.scrollAccelerationTarget == target,
       window > 0,
       now.timeIntervalSince(state.scrollAccelerationLastEventAt) <= window {
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
        || (state.pendingAcceleratedScrollLines != 0 && state.pendingAcceleratedScrollLines.signum() != lineDelta.signum()) {
        cancelPendingAcceleratedScroll(state: state, resetBurst: false)
    }

    state.pendingAcceleratedScrollTarget = target
    state.pendingAcceleratedScrollLines += lineDelta

    guard state.scrollAccelerationTask == nil else { return }

    state.scrollAccelerationTask = Task { [weak state] in
        guard let state else { return }

        while !Task.isCancelled {
            let intervalMilliseconds = await MainActor.run {
                max(1, state.config.editor.scrollAccelerationStepIntervalMilliseconds)
            }
            try? await Task.sleep(for: .milliseconds(intervalMilliseconds))

            let shouldContinue = await MainActor.run { () -> Bool in
                guard state.config.editor.scrollAccelerationEnabled else {
                    cancelPendingAcceleratedScroll(state: state, resetBurst: false)
                    return false
                }
                guard !Task.isCancelled,
                      let resumedTarget = state.pendingAcceleratedScrollTarget,
                      state.pendingAcceleratedScrollLines != 0 else {
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
func cancelPendingAcceleratedScroll(state: EditorState, resetBurst: Bool) {
    state.scrollAccelerationTask?.cancel()
    state.scrollAccelerationTask = nil
    state.pendingAcceleratedScrollLines = 0
    state.pendingAcceleratedScrollTarget = nil
    if resetBurst {
        resetScrollAccelerationBurst(state: state)
    }
}

@MainActor
private func resetScrollAccelerationBurst(state: EditorState) {
    state.scrollAccelerationDirection = nil
    state.scrollAccelerationTarget = nil
    state.scrollAccelerationBurstCount = 0
    state.scrollAccelerationLastEventAt = .distantPast
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
    guard let position = TextEditorLayout.textPosition(
        for: editor,
        in: editorRect,
        row: mouseRow - 1,
        col: mouseCol - 1
    ) else {
        return
    }

    state.clearSelection()
    state.selection = TextSelection(anchor: position, head: position)
    state.cursorRow = position.row
    state.cursorCol = position.col
    state.mode = .editor
}

@MainActor
private func handleSelectionDrag(mouse: MouseEvent, editorRect: Rect, layout: LayoutMetrics, state: EditorState) {
    let contentTop = layout.contentStartRow
    let contentBottom = layout.contentStartRow + layout.contentRows

    if mouse.row <= contentTop {
        state.scrollOffset = max(0, state.scrollOffset - 1)
    } else if mouse.row >= contentBottom {
        state.scrollOffset = min(state.fileLineCount - 1, state.scrollOffset + 1)
    }

    let editor = makeEditorView(state: state)
    if let pos = TextEditorLayout.textPosition(for: editor, in: editorRect, row: mouse.row - 1, col: mouse.col - 1) {
        state.selection?.head = pos
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
    if let indicatorRect = TreePanelLayout.verticalScrollIndicatorRect(rowCount: treeRowCount, in: treeRect),
       pointerCol >= indicatorRect.x,
       pointerCol < indicatorRect.maxX,
       let gripOffset = TreePanelLayout.scrollGripOffset(
           rowCount: treeRowCount,
           scrollOffset: state.treeScrollOffset,
           in: treeRect,
           pointerRow: pointerRow
       ) {
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
    if let indicatorRect = TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: editorRect),
       pointerCol >= indicatorRect.x,
       pointerCol < indicatorRect.maxX,
       let gripOffset = TextEditorLayout.scrollGripOffset(for: editor, in: editorRect, pointerRow: pointerRow) {
        state.scrollDragState = EditorState.ScrollDragState(target: .editor, gripOffset: gripOffset)
        let pos = TextEditorLayout.scrollPosition(for: editor, in: editorRect, pointerRow: pointerRow, gripOffset: gripOffset)
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
       pointerCol >= hRect.x, pointerCol < hRect.maxX {
        let hMetrics = TextEditorLayout.horizontalScrollMetrics(
            for: editor, in: editorRect, maxLineWidth: state.maxLineWidth
        )
        if let gripOffset = HorizontalScrollIndicatorLayout.gripOffset(
            for: hMetrics, in: hRect, pointerCol: pointerCol
        ) {
            state.scrollDragState = EditorState.ScrollDragState(target: .editorHorizontal, gripOffset: gripOffset)
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
        let pos = TextEditorLayout.scrollPosition(for: editor, in: editorRect, pointerRow: pointerRow, gripOffset: dragState.gripOffset)
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
func makeEditorView(state: EditorState) -> TextEditor {
    TextEditor(
        buffer: state.textBuffer,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        wrapRowOffset: state.wrapRowOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        showsGutterDecorations: state.config.git.enabled && state.config.git.decorations.showLineChanges && state.gitLineDecorationProvider != nil,
        wrapLines: state.config.editor.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.editor.wrapLines,
        maxLineWidth: state.maxLineWidth,
        tabSize: state.config.editor.tabSize
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
func scrollLinesPerTick(visibleRows: Int, configured: Int?) -> Int {
    if let configured, configured > 0 {
        return configured
    }
    return 1
}
