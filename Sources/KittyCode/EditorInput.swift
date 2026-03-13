import KittyCodecs
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func handleEditorKey(
    _ key: KeyEvent, state: EditorState, contentRows: Int, pipeline: RenderPipeline
) -> Bool {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let editorRect = Rect(
        x: layout.editorStart,
        y: layout.contentStartRow,
        width: layout.editorWidth,
        height: layout.contentRows
    )
    let availWidth = max(
        1, TextEditorLayout.contentWidth(for: makeEditorView(state: state), in: editorRect))
    var shouldEnsureVisible = false
    var didDeleteSelection = false
    let isShiftHeld = key.modifiers.contains(.shift)

    if state.hasActiveSelection {
        if isNavigationKey(key) {
            if !isShiftHeld {
                // Plain navigation key: collapse selection to the appropriate edge
                guard let selection = state.selection else { return false }
                let (start, end) = selection.ordered
                switch key.keyCode {
                case Key.left.rawValue, Key.up.rawValue, Key.home.rawValue, Key.pageUp.rawValue:
                    state.cursorRow = start.row
                    state.cursorCol = start.col
                case Key.right.rawValue, Key.down.rawValue, Key.end.rawValue, Key.pageDown.rawValue:
                    state.cursorRow = end.row
                    state.cursorCol = end.col
                default:
                    break
                }
                state.clearSelection()
                ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
                return true
            }
            // shift+navigation: fall through to extend selection below
        } else if shouldReplaceSelectionBeforeHandling(key), let selection = state.selection {
            let previousSnapshot = state.activeBufferSnapshot()
            let mutation = TextOperations.deleteRange(
                in: &state.textBuffer, at: &state.textCursor, selection: selection)
            state.textDidChange(mutation, previousSnapshot: previousSnapshot)
            state.clearSelection()
            didDeleteSelection = true
        }
    }

    // Capture selection anchor before cursor movement for shift+navigation
    let anchorBeforeMove: TextPosition? =
        if isShiftHeld && isNavigationKey(key) {
            if let sel = state.selection {
                sel.anchor
            } else {
                TextPosition(row: state.cursorRow, col: state.cursorCol)
            }
        } else {
            nil
        }

    if state.config.keybindingMode == .vim && state.vimMode == .normal {
        switch key.keyCode {
        case AsciiKey.i:
            state.vimMode = .insert
            state.statusMessage = "-- INSERT -- [\(state.fileName)]"
        case AsciiKey.h:
            state.cursorCol = max(0, state.cursorCol - 1)
            shouldEnsureVisible = true
        case AsciiKey.j:
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileLineCount - 1))
            shouldEnsureVisible = true
        case AsciiKey.k:
            state.cursorRow = max(0, state.cursorRow - 1)
            shouldEnsureVisible = true
        case AsciiKey.l:
            let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
            state.cursorCol = min(state.cursorCol + 1, rowLength)
            shouldEnsureVisible = true
        case AsciiKey.colon:
            state.statusMessage = ":"
        case AsciiKey.w:
            if state.statusMessage == ":" {
                state.saveFile()
            }
        case AsciiKey.g where key.modifiers == .shift:
            state.cursorRow = max(0, state.fileLineCount - 1)
            shouldEnsureVisible = true
        default:
            break
        }
        if shouldEnsureVisible {
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        }
        return true
    }

    switch key.keyCode {
    case Key.down.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileLineCount - 1))
        } else {
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileLineCount - 1))
        }
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        shouldEnsureVisible = true
    case Key.up.rawValue:
        if key.modifiers.contains(.alt) {
            state.cursorRow = max(state.cursorRow - contentRows, 0)
        } else {
            state.cursorRow = max(state.cursorRow - 1, 0)
        }
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        shouldEnsureVisible = true
    case Key.left.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordBackward(state: state)
        } else {
            moveCursorLeft(state: state)
        }
        shouldEnsureVisible = true
    case Key.right.rawValue:
        if key.modifiers.contains(.alt) || key.modifiers.contains(.ctrl) {
            jumpWordForward(state: state)
        } else {
            moveCursorRight(state: state)
        }
        shouldEnsureVisible = true
    case AsciiKey.b where key.modifiers == .alt:
        jumpWordBackward(state: state)
        shouldEnsureVisible = true
    case AsciiKey.f where key.modifiers == .alt:
        jumpWordForward(state: state)
        shouldEnsureVisible = true
    case Key.home.rawValue:
        state.cursorCol = 0
        shouldEnsureVisible = true
    case Key.end.rawValue:
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = rowLength
        shouldEnsureVisible = true
    case Key.pageUp.rawValue:
        state.cursorRow = max(state.cursorRow - contentRows, 0)
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        shouldEnsureVisible = true
    case Key.pageDown.rawValue:
        state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileLineCount - 1))
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        shouldEnsureVisible = true
    case Key.enter.rawValue, Key.enterAlt.rawValue:
        let previousSnapshot = state.activeBufferSnapshot()
        let mutation = TextOperations.insertNewline(into: &state.textBuffer, at: &state.textCursor)
        state.textDidChange(mutation, previousSnapshot: previousSnapshot)
        shouldEnsureVisible = true
    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        if didDeleteSelection {
            // Selection was already deleted; don't also delete backward
            shouldEnsureVisible = true
        } else {
            let previousSnapshot = state.activeBufferSnapshot()
            if let mutation = TextOperations.deleteBackward(
                in: &state.textBuffer, at: &state.textCursor)
            {
                state.textDidChange(mutation, previousSnapshot: previousSnapshot)
                shouldEnsureVisible = true
            }
        }
    default:
        if let insertedText = textInsertion(for: key, allowTab: true) {
            insertText(insertedText, into: state)
            shouldEnsureVisible = true
        }
    }

    // Update selection for shift+navigation keys
    if let anchor = anchorBeforeMove {
        let head = TextPosition(row: state.cursorRow, col: state.cursorCol)
        state.selection = TextSelection(anchor: anchor, head: head)
    }

    if shouldEnsureVisible {
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    }
    return true
}

@MainActor
private func isNavigationKey(_ key: KeyEvent) -> Bool {
    switch key.keyCode {
    case Key.up.rawValue, Key.down.rawValue, Key.left.rawValue, Key.right.rawValue,
        Key.home.rawValue, Key.end.rawValue, Key.pageUp.rawValue, Key.pageDown.rawValue:
        return true
    default:
        return false
    }
}

@MainActor
private func shouldReplaceSelectionBeforeHandling(_ key: KeyEvent) -> Bool {
    switch key.keyCode {
    case Key.enter.rawValue, Key.enterAlt.rawValue, Key.backspace.rawValue,
        Key.backspaceAlt.rawValue, 9:
        return true
    default:
        return textInsertion(for: key, allowTab: true) != nil
    }
}
