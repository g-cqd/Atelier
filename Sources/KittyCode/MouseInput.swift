import Foundation
import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittyText

@MainActor
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorStart = 1 + treeWidth + 1
    let lineNumWidth = max(3, String(state.fileLineCount).count + 1)
    let scrollStep = scrollLinesPerTick(visibleRows: max(1, pipeline.rows - 2))

    if mouse.button.isScroll {
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

    state.isScrolling = false
    let now = Date()
    let isDoubleClick = now.timeIntervalSince(state.lastClickTime) < 0.3
    let contentRow = mouse.row - 2

    if mouse.col <= treeWidth && contentRow >= 0 {
        handleTreeClick(contentRow: contentRow, isDoubleClick: isDoubleClick, state: state)
    } else if contentRow >= 0 {
        handleEditorClick(
            row: contentRow,
            mouseCol: mouse.col,
            editorStart: editorStart,
            lineNumWidth: lineNumWidth,
            state: state
        )
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
private func handleEditorClick(row: Int, mouseCol: Int, editorStart: Int, lineNumWidth: Int, state: EditorState) {
    let lineIndex = state.scrollOffset + row
    guard lineIndex >= 0 && lineIndex < state.fileLineCount else { return }

    state.cursorRow = lineIndex
    state.mode = .editor

    let line = state.fileLine(at: lineIndex)
    let relativeCol = mouseCol - editorStart - lineNumWidth
    if state.config.wrapLines {
        let displayCol = max(0, relativeCol)
        state.cursorCol = charIndex(forDisplayColumn: displayCol, in: line)
    } else {
        let displayCol = max(0, relativeCol + state.hScrollOffset)
        state.cursorCol = charIndex(forDisplayColumn: displayCol, in: line)
    }
}

@MainActor
func scrollLinesPerTick(visibleRows: Int) -> Int {
    min(12, max(3, visibleRows / 8))
}
