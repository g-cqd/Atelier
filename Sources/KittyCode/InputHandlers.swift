import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer

enum Key: UInt32 {
    case up = 57352
    case down = 57353
    case right = 57354
    case left = 57355
    case enter = 13
    case enterAlt = 10
    case backspace = 127
    case backspaceAlt = 8
}

@MainActor
func handleEvent(event: InputEvent, state: EditorState, pipeline: RenderPipeline) -> Bool {
    let contentRows = pipeline.rows - 2

    switch event {
    case .key(let key):
        guard key.eventType == .press else { return true }
        state.isScrolling = false

        if key.modifiers == .ctrl {
            if key.keyCode == UInt32(Character("o").asciiValue!) {
                state.saveFile()
                return true
            }
            if key.keyCode == UInt32(Character("x").asciiValue!) {
                if state.mode == .editor {
                    state.mode = .tree
                    state.statusMessage = "Ready | ^O: Save, ^X: Quit"
                    return true
                }
                return false
            }
        }

        if key.keyCode == 27 {
            if state.mode == .editor {
                if state.config.keybindingMode == .vim {
                    state.vimMode = .normal
                    state.statusMessage = "-- NORMAL -- [\(state.fileName)] :w=Save, :q=Quit"
                } else {
                    state.mode = .tree
                    state.statusMessage = "Ready | ^O: Save, ^X: Quit"
                }
                return true
            }
            return false
        }

        if key.keyCode == 3 {
            return false
        }

        switch state.mode {
        case .tree:
            return handleTreeKey(key, state: state, contentRows: contentRows)
        case .editor:
            return handleEditorKey(key, state: state, contentRows: contentRows, pipeline: pipeline)
        }

    case .mouse(let mouse):
        handleMouse(mouse, state: state, pipeline: pipeline)
        return true

    default:
        return true
    }
}

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
            if state.fileContent.isEmpty {
                state.fileContent = [""]
            }
            var line = state.fileContent[state.cursorRow]
            let index = line.index(line.startIndex, offsetBy: state.cursorCol)
            line.insert(contentsOf: key.associatedText, at: index)
            state.fileContent[state.cursorRow] = line
            state.cursorCol += key.associatedText.count
        } else if key.keyCode < 256,
                  let scalar = UnicodeScalar(key.keyCode) {
            let char = Character(scalar)
            if char.isPrintable {
                if state.fileContent.isEmpty {
                    state.fileContent = [""]
                }
                var line = state.fileContent[state.cursorRow]
                let index = line.index(line.startIndex, offsetBy: state.cursorCol)
                line.insert(char, at: index)
                state.fileContent[state.cursorRow] = line
                state.cursorCol += 1
            }
        }
    }

    ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    return true
}

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
func handleMouse(_ mouse: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorStart = 1 + treeWidth + 1
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)

    if mouse.button.isScroll {
        state.isScrolling = true
        if mouse.col <= treeWidth {
            if mouse.button == .scrollUp {
                state.treeScrollOffset = max(0, state.treeScrollOffset - 3)
            } else if mouse.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.flatTree.count - 1), state.treeScrollOffset + 3)
            }
        } else {
            if mouse.button == .scrollUp {
                state.scrollOffset = max(0, state.scrollOffset - 3)
            } else if mouse.button == .scrollDown {
                state.scrollOffset = min(max(0, state.fileContent.count - 1), state.scrollOffset + 3)
            }
        }
    } else if mouse.kind == .press && mouse.button == .left {
        state.isScrolling = false
        let now = Date()
        let isDoubleClick = now.timeIntervalSince(state.lastClickTime) < 0.3
        let contentRow = mouse.row - 2

        if mouse.col <= treeWidth && contentRow >= 0 {
            let clickIndex = state.treeScrollOffset + contentRow
            if clickIndex >= 0 && clickIndex < state.flatTree.count {
                if isDoubleClick && clickIndex == state.lastClickIndex {
                    let entry = state.flatTree[clickIndex].entry
                    if entry.isDirectory {
                        state.toggleExpand(at: clickIndex)
                    } else {
                        state.openFile(at: clickIndex)
                        state.cursorCol = 0
                    }
                } else {
                    state.selectedTreeIndex = clickIndex
                    state.mode = .tree
                }
                state.lastClickIndex = clickIndex
            }
        } else if contentRow >= 0 {
            let lineIndex = state.scrollOffset + contentRow
            if lineIndex >= 0 && lineIndex < state.fileContent.count {
                state.cursorRow = lineIndex
                state.mode = .editor
                let line = state.fileContent[lineIndex]
                let relativeCol = mouse.col - editorStart - lineNumWidth
                if state.config.wrapLines {
                    state.cursorCol = min(max(0, relativeCol), line.count)
                } else {
                    state.cursorCol = min(max(0, relativeCol + state.hScrollOffset), line.count)
                }
            }
        }
        state.lastClickTime = now
    }
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