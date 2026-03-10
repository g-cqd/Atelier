import KittyCodecs

@MainActor
func jumpWordForward(state: EditorState) {
    guard !state.fileContent.isEmpty else { return }
    let chars = Array(state.fileContent[state.cursorRow])
    guard state.cursorCol < chars.count else { return }

    var pos = state.cursorCol
    while pos < chars.count && !chars[pos].isWhitespace {
        pos += 1
    }
    while pos < chars.count && chars[pos].isWhitespace {
        pos += 1
    }
    state.cursorCol = min(pos, chars.count)
}

@MainActor
func jumpWordBackward(state: EditorState) {
    guard !state.fileContent.isEmpty else { return }
    let chars = Array(state.fileContent[state.cursorRow])
    guard state.cursorCol > 0 else { return }

    var pos = max(0, state.cursorCol - 1)
    while pos > 0 && chars[pos].isWhitespace {
        pos -= 1
    }
    while pos > 0 && !chars[pos].isWhitespace {
        pos -= 1
    }
    if pos > 0 && chars[pos].isWhitespace {
        pos += 1
    }
    state.cursorCol = pos
}

@MainActor
func ensureEditorVisible(_ state: EditorState, contentRows: Int = 20, availWidth: Int = 80) {
    state.cursorRow = max(0, state.cursorRow)
    if state.cursorRow < state.scrollOffset {
        state.scrollOffset = state.cursorRow
    } else if state.cursorRow >= state.scrollOffset + contentRows {
        state.scrollOffset = max(0, state.cursorRow - contentRows + 1)
    }

    if !state.config.wrapLines {
        if state.cursorCol < state.hScrollOffset {
            state.hScrollOffset = state.cursorCol
        } else if state.cursorCol >= state.hScrollOffset + availWidth {
            state.hScrollOffset = max(0, state.cursorCol - availWidth + 1)
        }
    } else {
        state.hScrollOffset = 0
    }
}