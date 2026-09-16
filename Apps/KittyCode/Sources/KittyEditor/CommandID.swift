public enum CommandID: String, CaseIterable, Sendable {
    // Global
    case saveFile
    case newFile
    case closeTab
    case toggleSidebar
    case cycleFileVisibility

    // Tab navigation
    case nextTab
    case previousTab

    // Clipboard
    case copy
    case cut
    case paste

    // History
    case undo
    case redo

    // Ctrl+X has dual behavior depending on context
    case handleCtrlX

    // Escape and force quit
    case escapeEditor
    case forceQuit

    // Editor word navigation
    case editorWordForward
    case editorWordBackward

    // Editor navigation
    case editorMoveDown
    case editorMoveUp
    case editorMoveLeft
    case editorMoveRight
    case editorMoveDownPage
    case editorMoveUpPage
    case editorHome
    case editorEnd

    // Editor editing
    case editorInsertNewline
    case editorDeleteBackward

    // Search
    case searchOpenFile
    case searchOpenPanel
    case searchOpenWorkspace
    case searchNext
    case searchPrevious
    case searchClose
    case searchToggleReplace
    case searchReplaceOne
    case searchReplaceAll
    case searchToggleCase
    case searchToggleRegex
    case searchToggleWholeWord

    // Search panel focus
    case searchFocusFind
    case searchFocusReplace
    case searchFocusResults

    // Prompt
    case promptConfirm
    case promptCancel

    // Context menu
    case contextMenuUp
    case contextMenuDown
    case contextMenuSelect
    case contextMenuDismiss

    // Vim normal mode
    case vimEnterInsert
    case vimEnterCommandLine
    case vimMoveLeft
    case vimMoveDown
    case vimMoveUp
    case vimMoveRight
    case vimGotoLastLine

    // Vim visual mode
    case vimEnterVisual
    case vimEnterVisualLine
    case vimExitVisual

    // Vim motions
    case vimMoveWordForward
    case vimMoveWordBackward
    case vimMoveLineStart
    case vimMoveLineEnd
    case vimGotoFirstLine

    // Vim editing
    case vimDeleteLine
    case vimYankLine
    case vimPaste
    case vimSearchForward

    public var isTreeNavigation: Bool {
        switch self {
            case .treeDown, .treeUp:
                return true
            default:
                return false
        }
    }

    public var isEditorNavigation: Bool {
        switch self {
            case .editorMoveDown, .editorMoveUp, .editorMoveLeft, .editorMoveRight,
                .editorMoveDownPage, .editorMoveUpPage, .editorHome, .editorEnd,
                .editorWordForward, .editorWordBackward:
                return true
            default:
                return false
        }
    }

    // Tree navigation
    case treeDown
    case treeUp
    case treeSelect
    case treeExpandOrOpen
    case treeCollapse

    // Focus cycling
    case focusNext
    case focusPrevious
}
