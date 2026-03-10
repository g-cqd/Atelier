import KittyInput
import KittyRenderer

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