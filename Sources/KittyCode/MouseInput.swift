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

    if mouse.button.isScroll {
        state.scrollDragState = nil
        let now = Date()
        let momentumBlockInterval = TimeInterval(max(0, state.config.editor.scrollMomentumBlockMilliseconds)) / 1000

        if shouldCancelPendingAcceleratedScroll(for: mouse.button, state: state) {
            cancelPendingAcceleratedScroll(state: state, resetBurst: true)
        }

        if let blockedDirection = state.blockedMomentumDirection {
            if now < state.blockedMomentumDeadline, mouse.button == blockedDirection {
                state.blockedMomentumDirection = nil
                state.blockedMomentumDeadline = .distantPast
                return
            }

            if now >= state.blockedMomentumDeadline {
                state.blockedMomentumDirection = nil
                state.blockedMomentumDeadline = .distantPast
            }
        }

        let previousDirection = state.lastScrollDirection
        if let previousDirection, previousDirection.isScroll, previousDirection != mouse.button, momentumBlockInterval > 0 {
            // After a reversal, ignore at most one immediate rebound event from the old direction.
            state.blockedMomentumDirection = previousDirection
            state.blockedMomentumDeadline = now.addingTimeInterval(momentumBlockInterval)
        }
        state.lastScrollDirection = mouse.button

        state.isScrolling = true

        // Scroll wheel on tab ribbon row
        if layout.showTabRibbon && mouse.row == layout.contentStartRow && mouse.col - 1 >= layout.editorStart {
            if mouse.button == .scrollUp || mouse.button == .scrollLeft {
                state.tabScrollOffset = max(0, state.tabScrollOffset - 1)
            } else if mouse.button == .scrollDown || mouse.button == .scrollRight {
                state.tabScrollOffset = min(max(0, state.bufferManager.count - 1), state.tabScrollOffset + 1)
            }
            return
        }

        if mouse.col - 1 < layout.editorStart {
            if mouse.button == .scrollUp {
                scrollVertically(
                    target: .tree,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            } else if mouse.button == .scrollDown {
                scrollVertically(
                    target: .tree,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            }
        } else if !state.config.editor.wrapLines,
                  mouse.button == .scrollLeft || mouse.button == .scrollRight ||
                  (mouse.modifiers.contains(.shift) && (mouse.button == .scrollUp || mouse.button == .scrollDown)) {
            let hStep = state.config.editor.scrollHorizontalStep
            if mouse.button == .scrollUp || mouse.button == .scrollLeft {
                scrollEditorHorizontally(state: state, editorRect: editorRect, delta: -hStep)
            } else if mouse.button == .scrollDown || mouse.button == .scrollRight {
                scrollEditorHorizontally(state: state, editorRect: editorRect, delta: hStep)
            }
        } else {
            if mouse.button == .scrollUp {
                scrollVertically(
                    target: .editor,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            } else if mouse.button == .scrollDown {
                scrollVertically(
                    target: .editor,
                    direction: mouse.button,
                    scrollStep: scrollStep,
                    state: state,
                    at: now
                )
            }
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
private func scrollVertically(
    target: EditorState.AcceleratedScrollTarget,
    direction: MouseButton,
    scrollStep: Int,
    state: EditorState,
    at now: Date
) {
    let unitDelta = direction == .scrollUp ? -scrollStep : scrollStep
    let directionChanged = state.scrollAccelerationDirection != nil && state.scrollAccelerationDirection != direction
    if directionChanged {
        cancelPendingAcceleratedScroll(state: state, resetBurst: false)
    }

    applyVerticalScrollDelta(unitDelta, target: target, state: state)

    let extraLines = extraAcceleratedScrollLines(
        for: direction,
        target: target,
        scrollStep: scrollStep,
        state: state,
        at: now
    )
    guard extraLines > 0 else { return }
    enqueueAcceleratedScroll(lineDelta: direction == .scrollUp ? -extraLines : extraLines, target: target, state: state)
}

@MainActor
private func applyVerticalScrollDelta(
    _ delta: Int,
    target: EditorState.AcceleratedScrollTarget,
    state: EditorState
) {
    switch target {
    case .tree:
        state.treeScrollOffset = min(
            max(0, state.cachedFlatTree.count - 1),
            max(0, state.treeScrollOffset + delta)
        )
    case .editor:
        state.scrollOffset = min(
            max(0, state.fileLineCount - 1),
            max(0, state.scrollOffset + delta)
        )
    }
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
    return min(maxExtraLines, state.scrollAccelerationBurstCount / 2)
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
                applyVerticalScrollDelta(step, target: resumedTarget, state: state)
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

    state.cursorRow = position.row
    state.cursorCol = position.col
    state.mode = .editor
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
        state.scrollOffset = TextEditorLayout.scrollOffset(
            for: editor,
            in: editorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )
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
        state.scrollOffset = TextEditorLayout.scrollOffset(
            for: editor,
            in: editorRect,
            pointerRow: pointerRow,
            gripOffset: dragState.gripOffset
        )
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
private func scrollEditorHorizontally(state: EditorState, editorRect: Rect, delta: Int) {
    let editor = makeEditorView(state: state)
    let metrics = TextEditorLayout.horizontalScrollMetrics(
        for: editor,
        in: editorRect,
        maxLineWidth: state.maxLineWidth
    )
    state.hScrollOffset = min(
        metrics.maxOffset,
        max(0, state.hScrollOffset + delta)
    )
}

@MainActor
func scrollLinesPerTick(visibleRows: Int, configured: Int?) -> Int {
    if let configured, configured > 0 {
        return configured
    }
    return 1
}
