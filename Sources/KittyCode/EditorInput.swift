import KittyCodecs
import KittyRenderer

@MainActor
func handleEditorKey(_ key: KeyEvent, state: EditorState, contentRows: Int, pipeline: RenderPipeline) -> Bool {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorWidth = pipeline.columns - treeWidth - 1
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    let availWidth = editorWidth - lineNumWidth

    if state.config.keybindingMode == .vim && state.vimMode == .normal {
        switch key.keyCode {
        case UInt32(Character("i").asciiValue!):
            state.vimMode = .insert
            state.statusMessage = "-- INSERT -- [\(state.fileName)]"
        case UInt32(Character("h").asciiValue!):
            state.cursorCol = max(0, state.cursorCol - 1)
        case UInt32(Character("j").asciiValue!):
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
        case UInt32(Character("k").asciiValue!):
            state.cursorRow = max(0, state.cursorRow - 1)
        case UInt32(Character("l").asciiValue!):
            let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLength)
        case UInt32(Character(":").asciiValue!):
            state.statusMessage = ":"
        case UInt32(Character("w").asciiValue!):
            if state.statusMessage == ":" {
                state.saveFile()
            }
        default:
            break
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        return true
    }

    switch key.keyCode {
    case Key.down.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
        } else {
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
        }
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.up.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = max(state.cursorRow - contentRows, 0)
        } else {
            state.cursorRow = max(state.cursorRow - 1, 0)
        }
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.left.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordBackward(state: state)
        } else {
            state.cursorCol = max(state.cursorCol - 1, 0)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.right.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordForward(state: state)
        } else {
            let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLength)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case UInt32(Character("b").asciiValue!):
        if key.modifiers == .alt {
            jumpWordBackward(state: state)
        }
    case UInt32(Character("f").asciiValue!):
        if key.modifiers == .alt {
            jumpWordForward(state: state)
        }
    case 57356:
        state.cursorCol = 0
    case 57357:
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = rowLength
    case 57358:
        state.cursorRow = max(state.cursorRow - contentRows, 0)
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case 57359:
        state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
        let rowLength = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.enter.rawValue, Key.enterAlt.rawValue:
        guard !state.fileContent.isEmpty else {
            state.fileContent = [""]
            state.cursorRow = 0
            state.cursorCol = 0
            return true
        }
        let currentLine = state.fileContent[state.cursorRow]
        let prefix = String(currentLine.prefix(state.cursorCol))
        let suffix = String(currentLine.dropFirst(state.cursorCol))
        state.fileContent[state.cursorRow] = prefix
        state.fileContent.insert(suffix, at: state.cursorRow + 1)
        state.cursorRow += 1
        state.cursorCol = 0
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        if state.cursorCol > 0 {
            var line = state.fileContent[state.cursorRow]
            let index = line.index(line.startIndex, offsetBy: state.cursorCol - 1)
            line.remove(at: index)
            state.fileContent[state.cursorRow] = line
            state.cursorCol -= 1
        } else if state.cursorRow > 0 {
            let line = state.fileContent.remove(at: state.cursorRow)
            state.cursorRow -= 1
            state.cursorCol = state.fileContent[state.cursorRow].count
            state.fileContent[state.cursorRow] += line
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        }
    case UInt32(Character("g").asciiValue!):
        if key.modifiers == .shift {
            state.cursorRow = max(0, state.fileContent.count - 1)
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        } else {
            state.cursorRow = 0
            state.cursorCol = 0
            state.scrollOffset = 0
        }
    default:
        if !key.associatedText.isEmpty {
            insertText(key.associatedText, into: state)
        } else if key.keyCode < 256, let scalar = UnicodeScalar(key.keyCode) {
            let char = Character(scalar)
            if char.isPrintable {
                insertText(String(char), into: state)
            }
        }
    }

    ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    return true
}
