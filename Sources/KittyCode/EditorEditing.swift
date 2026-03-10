@MainActor
func insertText(_ text: String, into state: EditorState) {
    if state.fileContent.isEmpty {
        state.fileContent = [""]
    }
    var line = state.fileContent[state.cursorRow]
    let index = line.index(line.startIndex, offsetBy: state.cursorCol)
    line.insert(contentsOf: text, at: index)
    state.fileContent[state.cursorRow] = line
    state.cursorCol += text.count
}