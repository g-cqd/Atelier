import KittyText

@MainActor
func insertText(_ text: String, into state: EditorState) {
    let lineBeforeInsert = state.textCursor.row
    TextOperations.insert(text, into: &state.textBuffer, at: &state.textCursor)
    state.invalidateTextSnapshotCache()

    let maxLine = max(lineBeforeInsert, state.textCursor.row)
    if text.contains("\n") || text.contains("\r") {
        let keys = state.highlightCache.keys.filter { $0 >= lineBeforeInsert }
        for key in keys {
            state.highlightCache.removeValue(forKey: key)
        }
    } else {
        state.invalidateHighlightCache(lines: lineBeforeInsert..<(maxLine + 1))
    }
}
