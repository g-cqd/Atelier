import KittyFileTree
import KittyRenderer
import KittyText
import KittyWidgets

@MainActor
func dispatchCommand(
    _ command: CommandID,
    state: EditorState,
    pipeline: RenderPipeline
) -> Bool {
    switch command {
    case .saveFile:
        state.saveFile()
        return true

    case .newFile:
        state.beginNewFile()
        return true

    case .closeTab:
        if state.bufferManager.count > 0 {
            state.closeCurrentTab()
        }
        return true

    case .toggleSidebar:
        state.sidebarCollapsed.toggle()
        return true

    case .cycleFileVisibility:
        Task { @MainActor in
            await state.cycleFileVisibility()
            state.renderRefreshSource?.invalidate()
        }
        return true

    case .nextTab:
        state.saveStateToActiveBuffer()
        state.bufferManager.nextTab()
        state.restoreStateFromActiveBuffer()
        state.ensureActiveTabVisible(
            ribbonWidth: max(
                0,
                pipeline.columns
                    - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
        return true

    case .previousTab:
        state.saveStateToActiveBuffer()
        state.bufferManager.prevTab()
        state.restoreStateFromActiveBuffer()
        state.ensureActiveTabVisible(
            ribbonWidth: max(
                0,
                pipeline.columns
                    - LayoutMetrics.editorStart(state: state, columns: pipeline.columns)))
        return true

    case .copy:
        if state.hasActiveSelection {
            handleCopy(state: state)
        }
        return true

    case .cut:
        if state.hasActiveSelection {
            handleCut(state: state)
        }
        return true

    case .paste:
        handlePasteRequest(state: state)
        return true

    case .undo:
        state.performUndo()
        return true

    case .redo:
        state.performRedo()
        return true

    case .handleCtrlX:
        // Dual behavior: cut if clipboard modifier includes control and selection active,
        // otherwise exit to tree or quit
        if state.config.keybindings.clipboardModifier == .control
            || state.config.keybindings.clipboardModifier == .both
        {
            if state.hasActiveSelection {
                handleCut(state: state)
                return true
            }
        }
        if state.mode == .editor {
            state.mode = .tree
            let resolver = KeymapResolver(config: state.config)
            state.statusMessage = "Ready | \(resolver.statusHints())"
            return true
        }
        // Tree mode: quit
        return false

    case .searchOpenFile:
        openInFileSearch(state: state)
        return true

    case .searchOpenPanel:
        state.activeSidebarPanel = .search
        state.sidebarCollapsed = false
        if state.inFileSearch == nil {
            openInFileSearch(state: state)
        }
        state.searchTarget = .currentFile
        state.mode = .searchPanel
        state.searchPanelSelectedIndex = -1
        state.searchPanelFocus = .findField
        return true

    case .searchOpenWorkspace:
        state.activeSidebarPanel = .search
        state.sidebarCollapsed = false
        if state.inFileSearch == nil {
            openInFileSearch(state: state)
        }
        state.searchTarget = .workspace
        state.mode = .searchPanel
        state.searchPanelSelectedIndex = -1
        state.searchPanelFocus = .findField
        if let search = state.inFileSearch, !search.query.isEmpty {
            triggerWorkspaceSearch(state: state)
        }
        return true

    case .searchNext:
        if state.inFileSearch != nil {
            stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
        }
        return true

    case .searchPrevious:
        if state.inFileSearch != nil {
            stepSearchMatch(direction: .previous, state: state, pipeline: pipeline)
        }
        return true

    case .searchClose:
        state.inFileSearch = nil
        state.workspaceSearchTask?.cancel()
        state.workspaceSearchTask = nil
        state.workspaceSearchResults = []
        state.isSearchingWorkspace = false
        return true

    case .searchToggleReplace:
        if state.inFileSearch != nil {
            state.inFileSearch?.showReplace.toggle()
        }
        return true

    case .searchReplaceOne:
        replaceCurrentMatch(state: state, pipeline: pipeline)
        return true

    case .searchReplaceAll:
        if state.searchTarget == .workspace {
            // Workspace replace-all needs confirmation
            let matchCount = state.workspaceSearchResults.reduce(0) { $0 + $1.matches.count }
            let fileCount = state.workspaceSearchResults.count
            if matchCount > 0 {
                state.prompt = EditorPrompt(
                    kind: .confirmReplaceAll(matchCount: matchCount, fileCount: fileCount),
                    promptText: "Replace \(matchCount) matches in \(fileCount) files? [Enter] ",
                    input: ""
                )
            }
        } else {
            replaceAllInFile(state: state, pipeline: pipeline)
        }
        return true

    case .searchToggleCase:
        if state.inFileSearch != nil {
            state.inFileSearch?.isCaseSensitive.toggle()
            reExecuteSearch(state: state, pipeline: pipeline)
        }
        return true

    case .searchToggleRegex:
        if state.inFileSearch != nil {
            state.inFileSearch?.isRegex.toggle()
            reExecuteSearch(state: state, pipeline: pipeline)
        }
        return true

    case .escapeEditor:
        if state.mode == .editor {
            if state.config.keybindingMode == .vim {
                state.vimMode = .normal
                state.statusMessage = "-- NORMAL -- [\(state.fileName)] :w=Save, :q=Quit"
            } else {
                state.mode = .tree
                let resolver = KeymapResolver(config: state.config)
                state.statusMessage = "Ready | \(resolver.statusHints())"
            }
            return true
        }
        return false

    case .forceQuit:
        return false

    case .editorWordForward:
        jumpWordForward(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorWordBackward:
        jumpWordBackward(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveDown:
        state.cursorRow = min(state.cursorRow + 1, max(0, state.fileLineCount - 1))
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveUp:
        state.cursorRow = max(state.cursorRow - 1, 0)
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveLeft:
        moveCursorLeft(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveRight:
        moveCursorRight(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveDownPage:
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        state.cursorRow = min(
            state.cursorRow + layout.contentRows, max(0, state.fileLineCount - 1))
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorMoveUpPage:
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        state.cursorRow = max(state.cursorRow - layout.contentRows, 0)
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol, rowLength)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorHome:
        state.cursorCol = 0
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorEnd:
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = rowLength
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorInsertNewline:
        let previousSnapshot = state.activeBufferSnapshot()
        let mutation = TextOperations.insertNewline(
            into: &state.textBuffer, at: &state.textCursor)
        state.textDidChange(mutation, previousSnapshot: previousSnapshot)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .editorDeleteBackward:
        let previousSnapshot = state.activeBufferSnapshot()
        if let mutation = TextOperations.deleteBackward(
            in: &state.textBuffer, at: &state.textCursor)
        {
            state.textDidChange(mutation, previousSnapshot: previousSnapshot)
        }
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimEnterInsert:
        state.vimMode = .insert
        state.statusMessage = "-- INSERT -- [\(state.fileName)]"
        return true

    case .vimEnterCommandLine:
        state.vimCommandLine = VimCommandLine()
        state.statusMessage = ":"
        return true

    case .vimMoveLeft:
        state.cursorCol = max(0, state.cursorCol - 1)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveDown:
        state.cursorRow = min(state.cursorRow + 1, max(0, state.fileLineCount - 1))
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveUp:
        state.cursorRow = max(0, state.cursorRow - 1)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveRight:
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol + 1, rowLength)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimGotoLastLine:
        state.cursorRow = max(0, state.fileLineCount - 1)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .treeDown:
        state.selectedTreeIndex = min(
            state.selectedTreeIndex + 1, max(0, state.cachedFlatTree.count - 1))
        updateSelectedTreePath(state)
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        ensureTreeVisible(state, contentRows: layout.contentRows)
        return true

    case .treeUp:
        state.selectedTreeIndex = max(state.selectedTreeIndex - 1, 0)
        updateSelectedTreePath(state)
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        ensureTreeVisible(state, contentRows: layout.contentRows)
        return true

    case .treeSelect:
        guard state.selectedTreeIndex >= 0
            && state.selectedTreeIndex < state.cachedFlatTree.count
        else { return true }
        let entry = state.cachedFlatTree[state.selectedTreeIndex].node
        state.noteSelectedPath(entry.path, isDirectory: entry.isDirectory)
        if entry.isDirectory {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
        return true

    case .treeExpandOrOpen:
        guard state.selectedTreeIndex >= 0
            && state.selectedTreeIndex < state.cachedFlatTree.count
        else { return true }
        let entry = state.cachedFlatTree[state.selectedTreeIndex].node
        state.noteSelectedPath(entry.path, isDirectory: entry.isDirectory)
        if entry.isDirectory && !entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else if !entry.isDirectory {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
        return true

    case .treeCollapse:
        guard state.selectedTreeIndex >= 0
            && state.selectedTreeIndex < state.cachedFlatTree.count
        else { return true }
        let entry = state.cachedFlatTree[state.selectedTreeIndex].node
        state.noteSelectedPath(entry.path, isDirectory: entry.isDirectory)
        if entry.isDirectory && entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        }
        return true
    }
}

@MainActor
func ensureEditorVisibleFull(state: EditorState, pipeline: RenderPipeline) {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let editorRect = Rect(
        x: layout.editorStart, y: layout.contentStartRow,
        width: layout.editorWidth, height: layout.contentRows)
    let availWidth = max(
        1, TextEditorLayout.contentWidth(for: makeEditorView(state: state), in: editorRect))
    ensureEditorVisible(state, contentRows: layout.contentRows, availWidth: availWidth)
}
