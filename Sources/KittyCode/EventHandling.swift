import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyText

@MainActor
func handleEvent(event: InputEvent, state: EditorState, pipeline: RenderPipeline) -> Bool {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let contentRows = layout.contentRows

    switch event {
    case .key(let key):
        guard key.eventType != .release else { return true }
        cancelPendingAcceleratedScroll(state: state, resetBurst: true)
        state.isScrolling = false

        if state.contextMenu != nil {
            return state.handleContextMenuKey(key)
        }

        if state.prompt != nil {
            return state.handlePromptKey(key)
        }

        if state.vimCommandLine != nil {
            return state.handleVimCommandLineKey(key)
        }

        if state.inFileSearch != nil && state.mode != .searchPanel {
            return handleSearchKey(key, state: state, pipeline: pipeline)
        }

        if key.eventType == .press || key.eventType == .repeat {
            let stroke = KeyStroke(from: key)
            let context = KeyContext.from(state: state)
            let isRepeat = key.eventType == .repeat
            let resolver = KeymapResolver(config: state.config)
            if let command = resolver.resolve(stroke, context: context, isRepeat: isRepeat) {
                return dispatchEditorAwareCommand(
                    command, key: key, state: state, pipeline: pipeline)
            }
            // Shift+navigation: try resolving without shift so selection tracking can wrap it
            if key.modifiers.contains(.shift) {
                let strippedStroke = KeyStroke(
                    keyCode: stroke.keyCode, modifiers: stroke.modifiers.subtracting(.shift))
                if let command = resolver.resolve(
                    strippedStroke, context: context, isRepeat: isRepeat),
                    command.isEditorNavigation
                {
                    return dispatchEditorAwareCommand(
                        command, key: key, state: state, pipeline: pipeline)
                }
            }
        }

        switch state.mode {
        case .tree:
            return handleTreeKey(key, state: state, contentRows: contentRows)
        case .editor:
            return handleEditorKey(key, state: state, contentRows: contentRows, pipeline: pipeline)
        case .searchPanel:
            return handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

    case .paste(let text):
        handlePaste(text, state: state)
        return true

    case .mouse(let mouse):
        if state.prompt != nil {
            return true
        }
        handleMouse(mouse, state: state, pipeline: pipeline)
        return true

    default:
        return true
    }
}

@MainActor
private func dispatchEditorAwareCommand(
    _ command: CommandID, key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    let isShiftHeld = key.modifiers.contains(.shift)

    // Selection handling for navigation commands
    if command.isEditorNavigation {
        if state.hasActiveSelection && !isShiftHeld {
            // Plain navigation: collapse selection to appropriate edge
            guard let selection = state.selection else {
                return dispatchCommand(command, state: state, pipeline: pipeline)
            }
            let (start, end) = selection.ordered
            switch command {
            case .editorMoveLeft, .editorMoveUp, .editorMoveUpPage, .editorHome,
                .editorWordBackward:
                state.cursorRow = start.row
                state.cursorCol = start.col
            default:
                state.cursorRow = end.row
                state.cursorCol = end.col
            }
            state.clearSelection()
            ensureEditorVisibleFull(state: state, pipeline: pipeline)
            return true
        }

        // Capture anchor for shift+navigation
        let anchor: TextPosition? =
            if isShiftHeld {
                if let sel = state.selection {
                    sel.anchor
                } else {
                    TextPosition(row: state.cursorRow, col: state.cursorCol)
                }
            } else {
                nil
            }

        let result = dispatchCommand(command, state: state, pipeline: pipeline)

        if let anchor = anchor {
            let head = TextPosition(row: state.cursorRow, col: state.cursorCol)
            state.selection = TextSelection(anchor: anchor, head: head)
        }

        return result
    }

    // Selection replacement for editing commands (insert/delete)
    if command == .editorInsertNewline || command == .editorDeleteBackward {
        if state.hasActiveSelection, let selection = state.selection {
            let previousSnapshot = state.activeBufferSnapshot()
            let mutation = TextOperations.deleteRange(
                in: &state.textBuffer, at: &state.textCursor, selection: selection)
            state.textDidChange(mutation, previousSnapshot: previousSnapshot)
            state.clearSelection()
            // For backspace, selection delete is sufficient — don't also delete backward
            if command == .editorDeleteBackward {
                ensureEditorVisibleFull(state: state, pipeline: pipeline)
                return true
            }
        }
    }

    return dispatchCommand(command, state: state, pipeline: pipeline)
}

@MainActor
func handleCopy(state: EditorState) {
    guard let selection = state.selection else { return }
    let text = selection.extractText(
        from: { state.fileLine(at: $0) }, lineCount: state.fileLineCount)
    let base64 = Data(text.utf8).base64EncodedString()
    state.terminalWriter?(KittySequences.setClipboard(base64))
    state.statusMessage = "Copied \(text.count) chars"
}

@MainActor
func handleCut(state: EditorState) {
    guard let selection = state.selection else { return }
    let text = selection.extractText(
        from: { state.fileLine(at: $0) }, lineCount: state.fileLineCount)
    let base64 = Data(text.utf8).base64EncodedString()
    state.terminalWriter?(KittySequences.setClipboard(base64))
    let previousSnapshot = state.activeBufferSnapshot()
    let mutation = TextOperations.deleteRange(
        in: &state.textBuffer, at: &state.textCursor, selection: selection)
    state.textDidChange(mutation, previousSnapshot: previousSnapshot)
    state.clearSelection()
    state.statusMessage = "Cut \(text.count) chars"
}

@MainActor
func handlePasteRequest(state: EditorState) {
    state.terminalWriter?(KittySequences.requestClipboard)
    state.statusMessage = "Paste request sent"
}

@MainActor
private func handlePaste(_ text: String, state: EditorState) {
    let sanitized = TextSanitizer.sanitize(text)

    if state.hasActiveSelection, let selection = state.selection {
        let previousSnapshot = state.activeBufferSnapshot()
        let mutation = TextOperations.deleteRange(
            in: &state.textBuffer, at: &state.textCursor, selection: selection)
        state.textDidChange(mutation, previousSnapshot: previousSnapshot)
        state.clearSelection()
    }

    let previousSnapshot = state.activeBufferSnapshot()
    let mutation = TextOperations.insert(
        sanitized.text, into: &state.textBuffer, at: &state.textCursor)
    state.textDidChange(mutation, previousSnapshot: previousSnapshot)

    if sanitized.replacedCount > 0 {
        state.statusMessage =
            "Pasted \(sanitized.text.count) chars (\(sanitized.replacedCount) non-printable replaced)"
    } else {
        state.statusMessage = "Pasted \(sanitized.text.count) chars"
    }
}
