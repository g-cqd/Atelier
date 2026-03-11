import KittyInput
import KittyRenderer

@MainActor
func handleEvent(event: InputEvent, state: EditorState, pipeline: RenderPipeline) -> Bool {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let contentRows = layout.contentRows

    switch event {
    case .key(let key):
        guard key.eventType != .release else { return true }
        state.isScrolling = false

        if state.prompt != nil {
            return state.handlePromptKey(key)
        }

        // Tab navigation (checked before mode dispatch)
        if key.eventType == .press, key.modifiers == .ctrl {
            if key.keyCode == Key.pageDown.rawValue {
                state.saveStateToActiveBuffer()
                state.bufferManager.nextTab()
                state.restoreStateFromActiveBuffer()
                state.ensureActiveTabVisible(ribbonWidth: max(0, pipeline.columns - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
                return true
            }
            if key.keyCode == Key.pageUp.rawValue {
                state.saveStateToActiveBuffer()
                state.bufferManager.prevTab()
                state.restoreStateFromActiveBuffer()
                state.ensureActiveTabVisible(ribbonWidth: max(0, pipeline.columns - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
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
            if key.keyCode == AsciiKey.w, state.config.keybindingMode == .nano, state.bufferManager.count > 0 {
                state.closeCurrentTab()
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
