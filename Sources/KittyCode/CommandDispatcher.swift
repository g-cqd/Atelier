import Foundation
import KittyCodecs
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

    case .searchToggleWholeWord:
        if state.inFileSearch != nil {
            state.inFileSearch?.isWholeWord.toggle()
            reExecuteSearch(state: state, pipeline: pipeline)
        }
        return true

    case .searchFocusFind:
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        return true

    case .searchFocusReplace:
        state.searchPanelFocus = .replaceField
        return true

    case .searchFocusResults:
        state.searchPanelFocus = .resultsList
        state.searchPanelSelectedIndex = max(0, state.inFileSearch?.activeMatchIndex ?? 0)
        return true

    case .promptConfirm:
        state.confirmPrompt()
        return true

    case .promptCancel:
        state.cancelPrompt()
        return true

    case .contextMenuUp:
        state.contextMenuMoveUp()
        return true

    case .contextMenuDown:
        state.contextMenuMoveDown()
        return true

    case .contextMenuSelect:
        state.contextMenuConfirm()
        return true

    case .contextMenuDismiss:
        state.dismissContextMenu()
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
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveDown:
        state.cursorRow = min(state.cursorRow + 1, max(0, state.fileLineCount - 1))
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveUp:
        state.cursorRow = max(0, state.cursorRow - 1)
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveRight:
        let rowLength = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = min(state.cursorCol + 1, rowLength)
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimGotoLastLine:
        state.cursorRow = max(0, state.fileLineCount - 1)
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimGotoFirstLine:
        state.cursorRow = 0
        state.cursorCol = 0
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimDeleteLine:
        guard !state.isFileEmpty else { return true }
        let deletePreviousSnapshot = state.activeBufferSnapshot()
        let deleteLineIndex = state.cursorRow
        let deleteLineCount = state.fileLineCount
        if deleteLineCount == 1 {
            let mutation = TextOperations.deleteLine(in: &state.textBuffer, at: &state.textCursor)
            state.textDidChange(mutation, previousSnapshot: deletePreviousSnapshot)
        } else {
            let mutation = TextOperations.deleteLine(in: &state.textBuffer, at: &state.textCursor)
            state.textDidChange(mutation, previousSnapshot: deletePreviousSnapshot)
            state.cursorRow = min(deleteLineIndex, state.fileLineCount - 1)
        }
        state.cursorCol = 0
        state.vimMode = .normal
        state.vimVisualAnchor = nil
        state.clearSelection()
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimYankLine:
        let yankRow = state.cursorRow
        let yankLine = state.fileLine(at: yankRow)
        let yankText = yankLine + "\n"
        let base64 = Data(yankText.utf8).base64EncodedString()
        state.terminalWriter?(KittySequences.setClipboard(base64))
        state.statusMessage = "Yanked line"
        state.vimMode = .normal
        state.vimVisualAnchor = nil
        state.clearSelection()
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

    case .vimEnterVisual:
        state.vimMode = .visual
        state.vimVisualAnchor = (line: state.cursorRow, col: state.cursorCol)
        state.selection = TextSelection(
            anchor: TextPosition(row: state.cursorRow, col: state.cursorCol),
            head: TextPosition(row: state.cursorRow, col: state.cursorCol))
        state.statusMessage = "-- VISUAL -- [\(state.fileName)]"
        return true

    case .vimEnterVisualLine:
        state.vimMode = .visualLine
        state.vimVisualAnchor = (line: state.cursorRow, col: 0)
        let visualLineLen = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.selection = TextSelection(
            anchor: TextPosition(row: state.cursorRow, col: 0),
            head: TextPosition(row: state.cursorRow, col: visualLineLen))
        state.statusMessage = "-- VISUAL LINE -- [\(state.fileName)]"
        return true

    case .vimExitVisual:
        state.vimMode = .normal
        state.vimVisualAnchor = nil
        state.clearSelection()
        state.statusMessage = "-- NORMAL -- [\(state.fileName)]"
        return true

    case .vimMoveWordForward:
        jumpWordForward(state: state)
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveWordBackward:
        jumpWordBackward(state: state)
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveLineStart:
        state.cursorCol = 0
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimMoveLineEnd:
        let lineEndLen = state.isFileEmpty ? 0 : state.fileLine(at: state.cursorRow).count
        state.cursorCol = lineEndLen
        updateVisualSelection(state: state)
        ensureEditorVisibleFull(state: state, pipeline: pipeline)
        return true

    case .vimPaste:
        handlePasteRequest(state: state)
        return true

    case .vimSearchForward:
        openInFileSearch(state: state)
        return true

    case .focusNext:
        switch state.mode {
        case .tree:
            state.mode = .editor
        case .editor:
            if state.activeSidebarPanel == .search && !state.sidebarCollapsed {
                state.mode = .searchPanel
                state.searchPanelFocus = .findField
            } else {
                state.mode = .tree
            }
        case .searchPanel:
            state.mode = .tree
        }
        return true

    case .focusPrevious:
        switch state.mode {
        case .tree:
            if state.activeSidebarPanel == .search && !state.sidebarCollapsed {
                state.mode = .searchPanel
                state.searchPanelFocus = .findField
            } else {
                state.mode = .editor
            }
        case .editor:
            state.mode = .tree
        case .searchPanel:
            state.mode = .editor
        }
        return true
    }
}

@MainActor
private func updateVisualSelection(state: EditorState) {
    guard state.vimMode == .visual || state.vimMode == .visualLine,
        let anchor = state.vimVisualAnchor
    else { return }
    state.selection = TextSelection(
        anchor: TextPosition(row: anchor.line, col: anchor.col),
        head: TextPosition(row: state.cursorRow, col: state.cursorCol))
}

@MainActor
func ensureEditorVisibleFull(state: EditorState, pipeline: RenderPipeline) {
    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
    let availWidth: Int
    if state.config.editor.wrapLines {
        availWidth = state.resolvedWrapContentWidth(columns: pipeline.columns, rows: pipeline.rows)
    } else {
        let editorRect = Rect(
            x: layout.editorStart,
            y: layout.contentStartRow,
            width: layout.editorWidth,
            height: layout.contentRows
        )
        availWidth = max(
            1,
            TextEditorLayout.contentWidth(for: makeEditorView(state: state), in: editorRect)
        )
    }
    ensureEditorVisible(state, contentRows: layout.contentRows, availWidth: availWidth)
}
