enum KeyContext: Sendable {
    case editor
    case editorVimNormal
    case editorVimCommandLine
    case editorVimVisual
    case tree
    case searchPanel
    case prompt
    case contextMenu

    @MainActor
    static func from(state: EditorState) -> KeyContext {
        if state.contextMenu != nil {
            return .contextMenu
        }
        if state.prompt != nil {
            return .prompt
        }
        switch state.mode {
        case .tree:
            return .tree
        case .editor:
            if state.config.keybindingMode == .vim {
                if state.vimCommandLine != nil {
                    return .editorVimCommandLine
                }
                if state.vimMode == .visual || state.vimMode == .visualLine {
                    return .editorVimVisual
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
