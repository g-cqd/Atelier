import KittyCodecs
import KittyFileTree

@MainActor
func handleTreeKey(_ key: KeyEvent, state: EditorState, contentRows: Int) -> Bool {
    // Navigation keys are now handled by KeymapResolver + CommandDispatcher.
    // This function remains as a fallback for any future tree-specific keys.
    return true
}

@MainActor
func updateSelectedTreePath(_ state: EditorState) {
    guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.cachedFlatTree.count
    else { return }
    let entry = state.cachedFlatTree[state.selectedTreeIndex].node
    state.noteSelectedPath(entry.path, isDirectory: entry.isDirectory)
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
