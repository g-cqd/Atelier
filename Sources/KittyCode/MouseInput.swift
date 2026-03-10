import Foundation
import KittyCodecs
import KittyRenderer

@MainActor
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorStart = 1 + treeWidth + 1
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)

    if mouse.button.isScroll {
        state.isScrolling = true
        if mouse.col <= treeWidth {
            if mouse.button == .scrollUp {
                state.treeScrollOffset = max(0, state.treeScrollOffset - 3)
            } else if mouse.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.flatTree.count - 1), state.treeScrollOffset + 3)
            }
        } else {
            if mouse.button == .scrollUp {
                state.scrollOffset = max(0, state.scrollOffset - 3)
            } else if mouse.button == .scrollDown {
                state.scrollOffset = min(max(0, state.fileContent.count - 1), state.scrollOffset + 3)
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
    guard clickIndex >= 0 && clickIndex < state.flatTree.count else { return }

    if isDoubleClick && clickIndex == state.lastClickIndex {
        let entry = state.flatTree[clickIndex].entry
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
    guard lineIndex >= 0 && lineIndex < state.fileContent.count else { return }

    state.cursorRow = lineIndex
    state.mode = .editor

    let line = state.fileContent[lineIndex]
    let relativeCol = mouseCol - editorStart - lineNumWidth
    if state.config.wrapLines {
        state.cursorCol = min(max(0, relativeCol), line.count)
    } else {
        state.cursorCol = min(max(0, relativeCol + state.hScrollOffset), line.count)
    }
}