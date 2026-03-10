import KittyText

@MainActor
func insertText(_ text: String, into state: EditorState) {
    let lineBeforeInsert = state.textCursor.row
    TextOperations.insert(text, into: &state.textBuffer, at: &state.textCursor)
    // Invalidate highlight cache from the edited line onward (newlines shift subsequent lines)
    let maxLine = max(lineBeforeInsert, state.textCursor.row)
    for line in lineBeforeInsert...maxLine {
        state.invalidateHighlightCache(line: line)
    }
    // If text contains newlines, invalidate all lines after the insertion point
    if text.contains("\n") || text.contains("\r") {
        let keys = state.highlightCache.keys.filter { $0 > lineBeforeInsert }
        for key in keys {
            state.highlightCache.removeValue(forKey: key)
        }
    }
}
