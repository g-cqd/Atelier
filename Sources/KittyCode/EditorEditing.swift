import KittyText

@MainActor
func insertText(_ text: String, into state: EditorState) {
    guard !text.isEmpty else { return }
    let previousSnapshot = state.activeBufferSnapshot()
    let mutation = TextOperations.insert(text, into: &state.textBuffer, at: &state.textCursor)
    state.textDidChange(mutation, previousSnapshot: previousSnapshot)
}
