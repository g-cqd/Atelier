import KittyCodecs

@MainActor
func handleTreeKey(_ key: KeyEvent, state: EditorState, contentRows: Int) -> Bool {
    switch key.keyCode {
    case Key.down.rawValue:
        state.selectedTreeIndex = min(state.selectedTreeIndex + 1, max(0, state.flatTree.count - 1))
        ensureTreeVisible(state, contentRows: contentRows)
    case Key.up.rawValue:
        state.selectedTreeIndex = max(state.selectedTreeIndex - 1, 0)
        ensureTreeVisible(state, contentRows: contentRows)
    case Key.enter.rawValue, Key.enterAlt.rawValue:
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
    case Key.right.rawValue:
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory && !entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else if !entry.isDirectory {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
    case Key.left.rawValue:
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory && entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        }
    default:
        break
    }
    return true
}

@MainActor
func ensureTreeVisible(_ state: EditorState, contentRows: Int = 20) {
    state.selectedTreeIndex = max(0, state.selectedTreeIndex)
    if state.selectedTreeIndex < state.treeScrollOffset {
        state.treeScrollOffset = state.selectedTreeIndex
    } else if state.selectedTreeIndex >= state.treeScrollOffset + contentRows {
        state.treeScrollOffset = max(0, state.selectedTreeIndex - contentRows + 1)
    }
}