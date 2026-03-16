enum KeyContext: Sendable {
    case editor
    case editorVimNormal
    case editorVimCommandLine
    case tree
    case searchPanel

    @MainActor
    static func from(state: EditorState) -> KeyContext {
        switch state.mode {
        case .tree:
            return .tree
        case .editor:
            if state.config.keybindingMode == .vim {
                if state.vimCommandLine != nil {
                    return .editorVimCommandLine
                }
                if state.vimMode == .normal {
                    return .editorVimNormal
                }
            }
            return .editor
        case .searchPanel:
            return .searchPanel
        }
    }
}
