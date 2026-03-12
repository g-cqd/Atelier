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

        if key.eventType == .press, isConfiguredUndoShortcut(key, config: state.config) {
            switch state.mode {
            case .editor:
                state.undoActiveBuffer()
            case .tree:
                Task { @MainActor in
                    await state.undoFileTreeOperation()
                }
            }
            return true
        }

        if key.eventType == .press, isConfiguredRedoShortcut(key, config: state.config) {
            switch state.mode {
            case .editor:
                state.redoActiveBuffer()
            case .tree:
                Task { @MainActor in
                    await state.redoFileTreeOperation()
                }
            }
            return true
        }

        if key.eventType == .press, isConfiguredCopyShortcut(key, config: state.config) {
            if state.hasActiveSelection {
                handleCopy(state: state)
            }
            return true
        }

        if key.eventType == .press, isConfiguredCutShortcut(key, config: state.config) {
            if state.hasActiveSelection {
                handleCut(state: state)
            }
            return true
        }

        if key.eventType == .press, isConfiguredPasteShortcut(key, config: state.config) {
            handlePasteRequest(state: state)
            return true
        }

        // Tab navigation (checked before mode dispatch)
        if key.eventType == .press, key.modifiers == .ctrl {
            if key.keyCode == Key.pageDown.rawValue {
                state.saveStateToActiveBuffer()
                state.bufferManager.nextTab()
                state.restoreStateFromActiveBuffer()
                state.ensureActiveTabVisible(
                    ribbonWidth: max(
                        0,
                        pipeline.columns
                            - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
                return true
            }
            if key.keyCode == Key.pageUp.rawValue {
                state.saveStateToActiveBuffer()
                state.bufferManager.prevTab()
                state.restoreStateFromActiveBuffer()
                state.ensureActiveTabVisible(
                    ribbonWidth: max(
                        0,
                        pipeline.columns
                            - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
                return true
            }
        }

        // Global hotkeys
        if key.eventType == .press, key.modifiers == .ctrl {
            if key.keyCode == AsciiKey.o {
                state.saveFile()
                return true
            }
            if key.keyCode == AsciiKey.n {
                state.beginNewFile()
                return true
            }
            if key.keyCode == AsciiKey.x {
                if state.hasActiveSelection {
                    handleCut(state: state)
                    return true
                }
                if state.mode == .editor {
                    state.mode = .tree
                    state.statusMessage = "Ready | ^O: Save, ^X: Quit"
                    return true
                }
                return false
            }
            // Ctrl+B toggles sidebar
            if key.keyCode == AsciiKey.b {
                state.sidebarCollapsed.toggle()
                return true
            }
            // Ctrl+W closes current tab (nano mode)
            if key.keyCode == AsciiKey.w, state.config.keybindingMode == .nano,
                state.bufferManager.count > 0
            {
                state.closeCurrentTab()
                return true
            }
            // Ctrl+H cycles file visibility (default → git-filtered → all)
            if key.keyCode == AsciiKey.h {
                Task { @MainActor in
                    await state.cycleFileVisibility()
                    state.renderRefreshSource?.invalidate()
                }
                return true
            }
        }

        if key.eventType == .press, key.keyCode == AsciiKey.escape {
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

        if key.eventType == .press, key.keyCode == 3 {
            return false
        }

        switch state.mode {
        case .tree:
            return handleTreeKey(key, state: state, contentRows: contentRows)
        case .editor:
            return handleEditorKey(key, state: state, contentRows: contentRows, pipeline: pipeline)
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
private func handleCopy(state: EditorState) {
    guard let selection = state.selection else { return }
    let text = selection.extractText(
        from: { state.fileLine(at: $0) }, lineCount: state.fileLineCount)
    let base64 = Data(text.utf8).base64EncodedString()
    state.terminalWriter?(KittySequences.setClipboard(base64))
    state.statusMessage = "Copied \(text.count) chars"
}

@MainActor
private func handleCut(state: EditorState) {
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
private func handlePasteRequest(state: EditorState) {
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
