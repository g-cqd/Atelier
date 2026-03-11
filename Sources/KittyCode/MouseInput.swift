import Foundation
import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let scrollStep = scrollLinesPerTick(visibleRows: max(1, layout.contentRows))

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
                state.treeScrollOffset = max(0, state.treeScrollOffset - scrollStep)
            } else if mouse.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.cachedFlatTree.count - 1), state.treeScrollOffset + scrollStep)
            }
        } else if !state.config.wrapLines,
                  mouse.button == .scrollLeft || mouse.button == .scrollRight ||
                  (mouse.modifiers.contains(.shift) && (mouse.button == .scrollUp || mouse.button == .scrollDown)) {
            let hStep = 4
            if mouse.button == .scrollUp || mouse.button == .scrollLeft {
                scrollEditorHorizontally(state: state, editorRect: editorRect, delta: -hStep)
            } else if mouse.button == .scrollDown || mouse.button == .scrollRight {
                scrollEditorHorizontally(state: state, editorRect: editorRect, delta: hStep)
            }
        } else {
            if mouse.button == .scrollUp {
                state.scrollOffset = max(0, state.scrollOffset - scrollStep)
            } else if mouse.button == .scrollDown {
                state.scrollOffset = min(max(0, state.fileLineCount - 1), state.scrollOffset + scrollStep)
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
        let tabs = state.bufferManager.buffers.map { buf in
            let status = state.config.showGitStatus && state.config.gitDecorations.showTabRibbonStatus
                ? state.fileStatusProvider?.status(for: buf.filePath)
                : nil
            return TabRibbon.Tab(
                name: buf.fileName,
                isDirty: buf.isDirty,
                isPreview: buf.isPreview,
                statusIndicator: status?.indicator.isEmpty == false ? status?.indicator : nil,
                statusStyle: status.map { state.colorScheme.gitStatusStyle(for: $0.statusColor) }
            )
        }
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: state.bufferManager.activeIndex,
            scrollOffset: state.tabScrollOffset
        )
        if let tabIdx = ribbon.tabIndex(atColumn: mouse.col - 1, ribbonX: layout.editorStart) {
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

    let tree = makeTreeView(state: state)
    if let indicatorRect = TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: treeRect),
       pointerCol >= indicatorRect.x,
       pointerCol < indicatorRect.maxX,
       let gripOffset = TreeViewLayout.scrollGripOffset(for: tree, in: treeRect, pointerRow: pointerRow) {
        state.scrollDragState = EditorState.ScrollDragState(target: .tree, gripOffset: gripOffset)
        state.treeScrollOffset = TreeViewLayout.scrollOffset(
            for: tree,
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
        let tree = makeTreeView(state: state)
        state.treeScrollOffset = TreeViewLayout.scrollOffset(
            for: tree,
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
private func makeTreeView(state: EditorState) -> TreeView<FileNode> {
    TreeView(
        root: state.treeNodes.map(makeTreeNodeForMouseInput),
        selectedIndex: state.selectedTreeIndex,
        scrollOffset: state.treeScrollOffset,
        showsVerticalScrollIndicator: true,
        label: { $0.name },
        rowStyle: { _ in .default }
    )
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
        showsGutterDecorations: state.config.showGitStatus && state.config.gitDecorations.showLineChanges && state.gitLineDecorationProvider != nil,
        wrapLines: state.config.wrapLines,
        showsVerticalScrollIndicator: true,
        showsHorizontalScrollIndicator: !state.config.wrapLines,
        maxLineWidth: state.maxLineWidth,
        tabSize: state.config.editor.tabSize
    )
}

private func makeTreeNodeForMouseInput(_ node: FileNode) -> TreeNode<FileNode> {
    TreeNode(
        value: node,
        children: node.children.map(makeTreeNodeForMouseInput),
        isExpanded: node.isExpanded
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
func scrollLinesPerTick(visibleRows: Int) -> Int {
    min(12, max(3, visibleRows / 8))
}
