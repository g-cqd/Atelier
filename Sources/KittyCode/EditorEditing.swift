import KittyText

@MainActor
func insertText(_ text: String, into state: EditorState) {
    TextOperations.insert(text, into: &state.textBuffer, at: &state.textCursor)
    state.invalidateTextSnapshotCache()
    state.refreshHighlights()
}
