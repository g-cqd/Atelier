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
        width: max(0, pipeline.columns - layout.editorStart),
        height: layout.contentRows
    )

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
        if mouse.col - 1 < layout.editorStart {
            if mouse.button == .scrollUp {
                state.treeScrollOffset = max(0, state.treeScrollOffset - scrollStep)
            } else if mouse.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.cachedFlatTree.count - 1), state.treeScrollOffset + scrollStep)
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

    guard mouse.kind == .press, mouse.button == .left else { return }

    // Tab ribbon click (mouse coords are 1-based, tab ribbon is at screen row 1)
    if layout.showTabRibbon && mouse.row == 2 && mouse.col - 1 >= layout.editorStart {
        let tabs = state.bufferManager.buffers.map { buf in
            TabRibbon.Tab(name: buf.fileName, isDirty: buf.isDirty)
        }
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: state.bufferManager.activeIndex,
            scrollOffset: state.tabScrollOffset
        )
        if let tabIdx = ribbon.tabIndex(atColumn: mouse.col - 1, ribbonX: layout.editorStart) {
            state.switchToTab(tabIdx)
            state.mode = .editor
        }
        return
    }

    // Activity bar click
    if state.config.activityBar.show && mouse.col - 1 < layout.activityBarWidth && mouse.row - 1 >= layout.contentStartRow {
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
        let relativeRow = mouse.row - 1 - layout.contentStartRow
        let bufferIdx = state.openFilesScrollOffset + relativeRow
        if bufferIdx >= 0, bufferIdx < state.bufferManager.count {
            state.switchToTab(bufferIdx)
            state.openFilesSelectedIndex = bufferIdx
            state.mode = .editor
        }
        return
    }

    if beginScrollDragIfNeeded(mouse: mouse, treeRect: treeRect, editorRect: editorRect, state: state) {
        return
    }

    state.isScrolling = false
    let now = Date()
    let isDoubleClick = now.timeIntervalSince(state.lastClickTime) < 0.3
    let contentRow = mouse.row - 1 - layout.contentStartRow

    if mouse.col - 1 >= layout.activityBarWidth && mouse.col - 1 < layout.editorStart - 1 && contentRow >= 0 {
        handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
    } else if mouse.col - 1 >= layout.editorStart && contentRow >= 0 {
        handleEditorClick(mouseRow: mouse.row, mouseCol: mouse.col, editorRect: editorRect, state: state)
    }

    state.lastClickTime = now
}

struct LayoutMetrics {
    let activityBarWidth: Int
    let sidebarWidth: Int
    let totalSidebarWidth: Int
    let editorStart: Int
    let contentStartRow: Int
    let contentRows: Int
    let showTabRibbon: Bool

    @MainActor
    init(state: EditorState, columns: Int, rows: Int) {
        let showAB = state.config.activityBar.show && !state.sidebarCollapsed
        self.activityBarWidth = showAB ? ActivityBar.width : 0
        self.showTabRibbon = state.config.tabRibbonPosition == .top && state.bufferManager.count > 0
        let tabRows = showTabRibbon ? 1 : 0
        self.contentStartRow = 1 + tabRows
        self.contentRows = max(0, rows - 2 - tabRows)

        if state.sidebarCollapsed {
            self.sidebarWidth = 0
        } else {
            self.sidebarWidth = min(state.treePanelWidth, columns / 2)
        }
        self.totalSidebarWidth = activityBarWidth + sidebarWidth
        let separatorWidth = sidebarWidth > 0 ? 1 : 0
        self.editorStart = totalSidebarWidth + separatorWidth
    }
}

@MainActor
private func handleTreeClick(contentRow: Int, isDoubleClick: Bool, state: EditorState) {
    let clickIndex = state.treeScrollOffset + contentRow
    guard clickIndex >= 0 && clickIndex < state.cachedFlatTree.count else { return }

    if isDoubleClick && clickIndex == state.lastClickIndex {
        let entry = state.cachedFlatTree[clickIndex].node
        if entry.isDirectory {
            state.toggleExpand(at: clickIndex)
        } else {
            state.openFile(at: clickIndex)
            state.cursorCol = 0
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
private func makeEditorView(state: EditorState) -> TextEditor {
    TextEditor(
        lines: state.fileContent,
        lineSpans: state.highlightedLines,
        scrollOffset: state.scrollOffset,
        horizontalScrollOffset: state.hScrollOffset,
        cursorRow: state.cursorRow,
        cursorCol: state.cursorCol,
        showLineNumbers: true,
        wrapLines: state.config.wrapLines,
        showsVerticalScrollIndicator: true
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
func scrollLinesPerTick(visibleRows: Int) -> Int {
    min(12, max(3, visibleRows / 8))
}
