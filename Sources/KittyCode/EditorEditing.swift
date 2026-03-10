import KittyText

@MainActor
func insertText(_ text: String, into state: EditorState) {
    guard !text.isEmpty else { return }
    let mutation = TextOperations.insert(text, into: &state.textBuffer, at: &state.textCursor)
    state.textDidChange(mutation)
}
