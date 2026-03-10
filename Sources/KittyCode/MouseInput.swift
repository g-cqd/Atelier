import Foundation
import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorStart = treeWidth + 2
    let contentRows = max(0, pipeline.rows - 2)
    let treeRect = Rect(x: 1, y: 1, width: treeWidth, height: contentRows)
    let editorRect = Rect(
        x: editorStart,
        y: 1,
        width: max(0, pipeline.columns - treeWidth - 1),
        height: contentRows
    )
    let scrollStep = scrollLinesPerTick(visibleRows: max(1, contentRows))

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
        if mouse.col <= treeWidth {
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

    if beginScrollDragIfNeeded(mouse: mouse, treeRect: treeRect, editorRect: editorRect, state: state) {
        return
    }

    state.isScrolling = false
    let now = Date()
    let isDoubleClick = now.timeIntervalSince(state.lastClickTime) < 0.3
    let contentRow = mouse.row - 2

    if mouse.col <= treeWidth && contentRow >= 0 {
        handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
    } else if contentRow >= 0 {
        handleEditorClick(mouseRow: mouse.row, mouseCol: mouse.col, editorRect: editorRect, state: state)
    }

    state.lastClickTime = now
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
        col: mouseCol
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
    let pointerRow = mouse.row - 1

    let tree = makeTreeView(state: state)
    if let indicatorRect = TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: treeRect),
       mouse.col >= indicatorRect.x,
       mouse.col < indicatorRect.maxX,
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
       mouse.col >= indicatorRect.x,
       mouse.col < indicatorRect.maxX,
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
