import KittyCodecs
import KittyInput
import KittyRenderer
import KittySearch
import KittyText

enum SearchStepDirection {
    case next
    case previous
}

@MainActor
func openInFileSearch(state: EditorState) {
    var prefill = ""
    if let selection = state.selection, !selection.isCollapsed {
        let (start, end) = selection.ordered
        if start.row == end.row {
            let line = state.fileLine(at: start.row)
            let startIdx = line.index(line.startIndex, offsetBy: min(start.col, line.count))
            let endIdx = line.index(line.startIndex, offsetBy: min(end.col, line.count))
            if startIdx < endIdx {
                prefill = String(line[startIdx..<endIdx])
            }
        }
    }

    var search = EditorState.InFileSearch(
        query: prefill,
        pattern: nil,
        matches: [],
        activeMatchIndex: -1,
        isCaseSensitive: state.config.search.caseSensitiveByDefault,
        isRegex: state.config.search.regexByDefault,
        isWholeWord: state.config.search.wholeWordByDefault
    )

    if !prefill.isEmpty {
        executeSearch(&search, lines: state.fileContent)
        search.activeMatchIndex = nearestMatchIndex(
            from: state.cursorRow, col: state.cursorCol, in: search.matches)
    }

    state.inFileSearch = search
}

@MainActor
func handleSearchKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    switch key.keyCode {
    case AsciiKey.escape:
        state.inFileSearch = nil
        return true

    case Key.enter.rawValue, Key.enterAlt.rawValue:
        if key.modifiers.contains(.shift) {
            stepSearchMatch(direction: .previous, state: state, pipeline: pipeline)
        } else {
            stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
        }
        return true

    case Key.up.rawValue:
        stepSearchMatch(direction: .previous, state: state, pipeline: pipeline)
        return true

    case Key.down.rawValue:
        stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
        return true

    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        guard var search = state.inFileSearch else { return true }
        if search.query.isEmpty {
            state.inFileSearch = nil
        } else {
            search.query.removeLast()
            executeSearch(&search, lines: state.fileContent)
            search.activeMatchIndex = nearestMatchIndex(
                from: state.cursorRow, col: state.cursorCol, in: search.matches)
            state.inFileSearch = search
            if let match = search.activeMatch {
                jumpToMatch(match, state: state, pipeline: pipeline)
            }
        }
        return true

    default:
        guard let text = textInsertion(for: key, allowTab: false) else { return true }
        guard var search = state.inFileSearch else { return true }
        search.query.append(text)
        executeSearch(&search, lines: state.fileContent)
        search.activeMatchIndex = nearestMatchIndex(
            from: state.cursorRow, col: state.cursorCol, in: search.matches)
        state.inFileSearch = search
        if let match = search.activeMatch {
            jumpToMatch(match, state: state, pipeline: pipeline)
        }
        return true
    }
}

@MainActor
func stepSearchMatch(
    direction: SearchStepDirection, state: EditorState, pipeline: RenderPipeline
) {
    guard var search = state.inFileSearch, !search.matches.isEmpty else { return }

    switch direction {
    case .next:
        search.activeMatchIndex = (search.activeMatchIndex + 1) % search.matches.count
    case .previous:
        search.activeMatchIndex =
            (search.activeMatchIndex - 1 + search.matches.count) % search.matches.count
    }

    state.inFileSearch = search
    if let match = search.activeMatch {
        jumpToMatch(match, state: state, pipeline: pipeline)
    }
}

@MainActor
func jumpToMatch(
    _ match: SearchMatch, state: EditorState, pipeline: RenderPipeline
) {
    state.cursorRow = match.row
    state.cursorCol = match.colStart
    ensureEditorVisibleFull(state: state, pipeline: pipeline)
}

func executeSearch(
    _ search: inout EditorState.InFileSearch, lines: [String]
) {
    let query = SearchQuery(
        text: search.query,
        isCaseSensitive: search.isCaseSensitive,
        isRegex: search.isRegex,
        wholeWord: search.isWholeWord
    )
    search.pattern = compilePattern(query)
    if let pattern = search.pattern {
        search.matches = findMatches(in: lines, pattern: pattern)
    } else {
        search.matches = []
    }
}

func nearestMatchIndex(
    from row: Int, col: Int, in matches: [SearchMatch]
) -> Int {
    guard !matches.isEmpty else { return -1 }

    var bestIndex = 0
    var bestDistance = Int.max

    for (index, match) in matches.enumerated() {
        let rowDist = abs(match.row - row)
        let colDist = match.row == row ? abs(match.colStart - col) : 0
        let distance = rowDist * 10000 + colDist
        if distance < bestDistance {
            bestDistance = distance
            bestIndex = index
        }
    }

    return bestIndex
}

@MainActor
func handleSearchPanelKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    // Tab key cycles focus / target
    if key.keyCode == AsciiKey.tab {
        if key.modifiers.contains(.shift) {
            // Shift+Tab: cycle search target
            state.searchTarget = state.searchTarget == .currentFile ? .workspace : .currentFile
            if state.searchTarget == .workspace {
                triggerWorkspaceSearch(state: state)
            }
        } else {
            // Tab: cycle focus between findField → replaceField (if visible) → resultsList
            switch state.searchPanelFocus {
            case .findField:
                if state.inFileSearch?.showReplace == true {
                    state.searchPanelFocus = .replaceField
                } else if let search = state.inFileSearch, !search.matches.isEmpty {
                    state.searchPanelFocus = .resultsList
                    state.searchPanelSelectedIndex = max(0, search.activeMatchIndex)
                    ensureSearchResultVisible(state: state)
                }
            case .replaceField:
                if let search = state.inFileSearch, !search.matches.isEmpty {
                    state.searchPanelFocus = .resultsList
                    state.searchPanelSelectedIndex = max(0, search.activeMatchIndex)
                    ensureSearchResultVisible(state: state)
                } else {
                    state.searchPanelFocus = .findField
                    state.searchPanelSelectedIndex = -1
                }
            case .resultsList:
                state.searchPanelFocus = .findField
                state.searchPanelSelectedIndex = -1
            }
        }
        return true
    }

    switch state.searchPanelFocus {
    case .findField:
        return handleSearchPanelFindFieldKey(key, state: state, pipeline: pipeline)
    case .replaceField:
        return handleSearchPanelReplaceFieldKey(key, state: state, pipeline: pipeline)
    case .resultsList:
        return handleSearchPanelResultsListKey(key, state: state, pipeline: pipeline)
    }
}

@MainActor
private func handleSearchPanelFindFieldKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    switch key.keyCode {
    case AsciiKey.escape:
        state.inFileSearch = nil
        state.workspaceSearchTask?.cancel()
        state.workspaceSearchTask = nil
        state.workspaceSearchResults = []
        state.isSearchingWorkspace = false
        state.mode = .editor
        return true

    case Key.enter.rawValue, Key.enterAlt.rawValue:
        if state.searchTarget == .currentFile {
            if let search = state.inFileSearch, !search.matches.isEmpty {
                state.searchPanelFocus = .resultsList
                state.searchPanelSelectedIndex = max(0, search.activeMatchIndex)
                state.searchPanelScrollOffset = 0
                ensureSearchResultVisible(state: state)
            }
        } else {
            if !state.workspaceSearchResults.isEmpty {
                state.searchPanelFocus = .resultsList
                state.searchPanelSelectedIndex = 0
                state.searchPanelScrollOffset = 0
            }
        }
        return true

    case Key.down.rawValue:
        if state.searchTarget == .currentFile {
            if let search = state.inFileSearch, !search.matches.isEmpty {
                state.searchPanelFocus = .resultsList
                state.searchPanelSelectedIndex = max(0, search.activeMatchIndex)
                state.searchPanelScrollOffset = 0
                ensureSearchResultVisible(state: state)
            }
        } else {
            if !state.workspaceSearchResults.isEmpty {
                state.searchPanelFocus = .resultsList
                state.searchPanelSelectedIndex = 0
                state.searchPanelScrollOffset = 0
            }
        }
        return true

    case Key.up.rawValue:
        return true

    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        guard var search = state.inFileSearch else { return true }
        if !search.query.isEmpty {
            search.query.removeLast()
            executeSearch(&search, lines: state.fileContent)
            search.activeMatchIndex = nearestMatchIndex(
                from: state.cursorRow, col: state.cursorCol, in: search.matches)
            state.inFileSearch = search
            state.searchPanelScrollOffset = 0
            if let match = search.activeMatch {
                jumpToMatch(match, state: state, pipeline: pipeline)
            }
            if state.searchTarget == .workspace {
                triggerWorkspaceSearchDebounced(state: state)
            }
        }
        return true

    default:
        guard let text = textInsertion(for: key, allowTab: false) else { return true }
        guard var search = state.inFileSearch else { return true }
        search.query.append(text)
        executeSearch(&search, lines: state.fileContent)
        search.activeMatchIndex = nearestMatchIndex(
            from: state.cursorRow, col: state.cursorCol, in: search.matches)
        state.inFileSearch = search
        state.searchPanelScrollOffset = 0
        if let match = search.activeMatch {
            jumpToMatch(match, state: state, pipeline: pipeline)
        }
        if state.searchTarget == .workspace {
            triggerWorkspaceSearchDebounced(state: state)
        }
        return true
    }
}

@MainActor
private func handleSearchPanelReplaceFieldKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    switch key.keyCode {
    case AsciiKey.escape:
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        return true

    case Key.enter.rawValue, Key.enterAlt.rawValue:
        // Enter in replace field: replace current match
        replaceCurrentMatch(state: state, pipeline: pipeline)
        return true

    case Key.up.rawValue:
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        return true

    case Key.down.rawValue:
        if let search = state.inFileSearch, !search.matches.isEmpty {
            state.searchPanelFocus = .resultsList
            state.searchPanelSelectedIndex = max(0, search.activeMatchIndex)
            ensureSearchResultVisible(state: state)
        }
        return true

    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        if state.inFileSearch != nil, !(state.inFileSearch?.replaceText.isEmpty ?? true) {
            state.inFileSearch?.replaceText.removeLast()
        }
        return true

    default:
        guard let text = textInsertion(for: key, allowTab: false) else { return true }
        state.inFileSearch?.replaceText.append(text)
        return true
    }
}

@MainActor
private func handleSearchPanelResultsListKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    if state.searchTarget == .workspace {
        return handleWorkspaceResultsListKey(key, state: state, pipeline: pipeline)
    }

    switch key.keyCode {
    case AsciiKey.escape:
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        return true

    case Key.up.rawValue:
        if state.searchPanelSelectedIndex <= 0 {
            state.searchPanelFocus = .findField
            state.searchPanelSelectedIndex = -1
        } else {
            state.searchPanelSelectedIndex -= 1
            state.inFileSearch?.activeMatchIndex = state.searchPanelSelectedIndex
            ensureSearchResultVisible(state: state)
            if let match = state.inFileSearch?.activeMatch {
                jumpToMatch(match, state: state, pipeline: pipeline)
            }
        }
        return true

    case Key.down.rawValue:
        let maxIdx = (state.inFileSearch?.matches.count ?? 1) - 1
        if state.searchPanelSelectedIndex < maxIdx {
            state.searchPanelSelectedIndex += 1
            state.inFileSearch?.activeMatchIndex = state.searchPanelSelectedIndex
            ensureSearchResultVisible(state: state)
            if let match = state.inFileSearch?.activeMatch {
                jumpToMatch(match, state: state, pipeline: pipeline)
            }
        }
        return true

    case Key.enter.rawValue, Key.enterAlt.rawValue:
        if let search = state.inFileSearch,
            state.searchPanelSelectedIndex >= 0,
            state.searchPanelSelectedIndex < search.matches.count
        {
            let match = search.matches[state.searchPanelSelectedIndex]
            state.cursorRow = match.row
            state.cursorCol = match.colStart
            state.mode = .editor
            ensureEditorVisibleFull(state: state, pipeline: pipeline)
        }
        return true

    default:
        // Printable chars: return to query field and append
        guard let text = textInsertion(for: key, allowTab: false) else { return true }
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        guard var search = state.inFileSearch else { return true }
        search.query.append(text)
        executeSearch(&search, lines: state.fileContent)
        search.activeMatchIndex = nearestMatchIndex(
            from: state.cursorRow, col: state.cursorCol, in: search.matches)
        state.inFileSearch = search
        state.searchPanelScrollOffset = 0
        if let match = search.activeMatch {
            jumpToMatch(match, state: state, pipeline: pipeline)
        }
        if state.searchTarget == .workspace {
            triggerWorkspaceSearchDebounced(state: state)
        }
        return true
    }
}

@MainActor
private func handleWorkspaceResultsListKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    let flatCount = workspaceFlatResultCount(state: state)

    switch key.keyCode {
    case AsciiKey.escape:
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        return true

    case Key.up.rawValue:
        if state.searchPanelSelectedIndex <= 0 {
            state.searchPanelFocus = .findField
            state.searchPanelSelectedIndex = -1
        } else {
            state.searchPanelSelectedIndex -= 1
            ensureSearchResultVisible(state: state)
        }
        return true

    case Key.down.rawValue:
        if state.searchPanelSelectedIndex < flatCount - 1 {
            state.searchPanelSelectedIndex += 1
            ensureSearchResultVisible(state: state)
        }
        return true

    case Key.enter.rawValue, Key.enterAlt.rawValue:
        if let (filePath, match) = workspaceFlatResult(
            at: state.searchPanelSelectedIndex, state: state)
        {
            openWorkspaceSearchResult(
                filePath: filePath, match: match, state: state, pipeline: pipeline)
        }
        return true

    default:
        guard let text = textInsertion(for: key, allowTab: false) else { return true }
        state.searchPanelFocus = .findField
        state.searchPanelSelectedIndex = -1
        guard var search = state.inFileSearch else { return true }
        search.query.append(text)
        executeSearch(&search, lines: state.fileContent)
        state.inFileSearch = search
        state.searchPanelScrollOffset = 0
        triggerWorkspaceSearchDebounced(state: state)
        return true
    }
}

// MARK: - Search scroll visibility

@MainActor
func ensureSearchResultVisible(state: EditorState) {
    let idx = state.searchPanelSelectedIndex
    guard idx >= 0 else { return }

    // The search panel uses approximately 5 header rows (header, query, toggles, summary, blank).
    // The visible results area height depends on the panel rect, but we estimate a reasonable
    // viewport height here. The actual viewport is `availRows` in renderSearchPanel.
    // We use the last known render dimensions to approximate.
    let headerRows = 5
    let panelHeight = state.lastRenderRows - 2  // minus status bar and title bar
    let availRows = max(1, panelHeight - headerRows)

    if idx < state.searchPanelScrollOffset {
        state.searchPanelScrollOffset = idx
    } else if idx >= state.searchPanelScrollOffset + availRows {
        state.searchPanelScrollOffset = idx - availRows + 1
    }
}

// MARK: - Workspace search helpers

@MainActor
func workspaceFlatResultCount(state: EditorState) -> Int {
    var count = 0
    for fileResult in state.workspaceSearchResults {
        count += 1  // file header
        count += fileResult.matches.count
    }
    return count
}

@MainActor
func workspaceFlatResult(
    at index: Int, state: EditorState
) -> (filePath: String, match: SearchMatch)? {
    var current = 0
    for fileResult in state.workspaceSearchResults {
        if current == index {
            // File header row - treat as first match
            if let first = fileResult.matches.first {
                return (fileResult.filePath, first)
            }
            return nil
        }
        current += 1
        for match in fileResult.matches {
            if current == index {
                return (fileResult.filePath, match)
            }
            current += 1
        }
    }
    return nil
}

@MainActor
func openWorkspaceSearchResult(
    filePath: String, match: SearchMatch, state: EditorState, pipeline: RenderPipeline
) {
    // Open file if not already open
    state.openFileByPath(filePath)
    state.cursorRow = match.row
    state.cursorCol = match.colStart
    state.mode = .editor
    ensureEditorVisibleFull(state: state, pipeline: pipeline)
}

@MainActor
func triggerWorkspaceSearch(state: EditorState) {
    guard let search = state.inFileSearch, !search.query.isEmpty else {
        state.workspaceSearchResults = []
        state.workspaceSearchSummary = ""
        state.isSearchingWorkspace = false
        return
    }

    let query = SearchQuery(
        text: search.query,
        isCaseSensitive: search.isCaseSensitive,
        isRegex: search.isRegex,
        wholeWord: search.isWholeWord
    )
    guard let pattern = compilePattern(query) else {
        state.workspaceSearchResults = []
        state.workspaceSearchSummary = search.isRegex ? "Invalid regex" : ""
        state.isSearchingWorkspace = false
        return
    }

    // Cancel previous workspace search
    state.workspaceSearchTask?.cancel()
    state.workspaceSearchResults = []
    state.isSearchingWorkspace = true
    state.workspaceSearchSummary = "Searching..."

    // Build open buffers dict
    var openBuffers: [String: [String]] = [:]
    for buffer in state.bufferManager.buffers {
        if !buffer.filePath.isEmpty {
            openBuffers[buffer.filePath] = buffer.textBuffer.lines
        }
    }

    let rootPath = state.rootPath
    let maxResults = state.config.search.maxResults

    state.workspaceSearchTask = Task { @MainActor in
        // Enumerate files off the main actor
        let files = await Task.detached {
            enumerateSearchableFiles(rootPath: rootPath)
        }.value

        guard !Task.isCancelled else { return }

        if files.isEmpty {
            state.workspaceSearchSummary = "No files to search"
            state.isSearchingWorkspace = false
            state.renderRefreshSource?.invalidate()
            return
        }

        let result = await Task.detached { [openBuffers] in
            await searchWorkspace(
                pattern: pattern,
                files: files,
                openBuffers: openBuffers,
                maxResults: maxResults,
                onProgress: { _ in }
            )
        }.value

        guard !Task.isCancelled else { return }

        state.workspaceSearchResults = result.results
        state.isSearchingWorkspace = false
        if result.totalMatchCount == 0 {
            state.workspaceSearchSummary = "No results"
        } else {
            state.workspaceSearchSummary =
                "\(result.totalMatchCount) matches in \(result.filesMatched) files"
        }
        state.renderRefreshSource?.invalidate()
    }
}

@MainActor
func triggerWorkspaceSearchDebounced(state: EditorState) {
    // Provide immediate UI feedback so the user sees the search panel
    // acknowledged the keystroke even before the debounce window elapses.
    state.isSearchingWorkspace = true
    state.workspaceSearchSummary = "Searching..."
    // The long-lived consumer on `EditorState` handles the debounce
    // window via `Task.sleep` inside its loop; `bufferingNewest(1)`
    // collapses bursts into a single subsequent search.
    state.workspaceSearchDebounceContinuation.yield(())
}

// MARK: - Replace operations

@MainActor
func replaceCurrentMatch(state: EditorState, pipeline: RenderPipeline) {
    guard let search = state.inFileSearch,
        let match = search.activeMatch,
        !state.readOnly
    else { return }

    let replacement = buildReplacementText(
        for: match,
        in: state.fileLine(at: match.row),
        pattern: search.pattern,
        replacement: search.replaceText
    )

    let previousSnapshot = state.activeBufferSnapshot()

    // Delete match range
    let startPos = TextPosition(row: match.row, col: match.colStart)
    let endPos = TextPosition(row: match.row, col: match.colEnd)
    let selection = TextSelection(anchor: startPos, head: endPos)
    let mutation = TextOperations.deleteRange(
        in: &state.textBuffer, at: &state.textCursor, selection: selection)
    state.textDidChange(mutation, previousSnapshot: previousSnapshot)

    // Insert replacement
    if !replacement.isEmpty {
        let previousSnapshot2 = state.activeBufferSnapshot()
        let mutation2 = TextOperations.insert(
            replacement, into: &state.textBuffer, at: &state.textCursor)
        state.textDidChange(mutation2, previousSnapshot: previousSnapshot2)
    }

    // Re-execute search and jump to next
    reExecuteSearch(state: state, pipeline: pipeline)
    stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
    state.statusMessage = "Replaced 1 match"
}

@MainActor
func replaceAllInFile(state: EditorState, pipeline: RenderPipeline) {
    guard let search = state.inFileSearch,
        !search.matches.isEmpty,
        !state.readOnly
    else { return }

    let previousSnapshot = state.activeBufferSnapshot()
    var lines = state.fileContent
    var replaceCount = 0

    // Apply replacements in reverse order to preserve positions
    for match in search.matches.reversed() {
        guard match.row >= 0, match.row < lines.count else { continue }
        let line = lines[match.row]
        let replacement = buildReplacementText(
            for: match, in: line, pattern: search.pattern, replacement: search.replaceText)

        let chars = Array(line)
        let before = String(chars.prefix(match.colStart))
        let after = String(chars.suffix(from: chars.index(chars.startIndex, offsetBy: match.colEnd)))
        lines[match.row] = before + replacement + after
        replaceCount += 1
    }

    state.fileContent = lines
    state.textDidChange(previousSnapshot: previousSnapshot)

    reExecuteSearch(state: state, pipeline: pipeline)
    state.statusMessage = "Replaced \(replaceCount) occurrences"
}

@MainActor
func reExecuteSearch(state: EditorState, pipeline: RenderPipeline) {
    guard var search = state.inFileSearch else { return }
    executeSearch(&search, lines: state.fileContent)
    search.activeMatchIndex = nearestMatchIndex(
        from: state.cursorRow, col: state.cursorCol, in: search.matches)
    state.inFileSearch = search
    if let match = search.activeMatch {
        jumpToMatch(match, state: state, pipeline: pipeline)
    }
    if state.searchTarget == .workspace {
        triggerWorkspaceSearchDebounced(state: state)
    }
}

private func buildReplacementText(
    for match: SearchMatch,
    in line: String,
    pattern: SearchPattern?,
    replacement: String
) -> String {
    guard let pattern else { return replacement }
    return buildReplacement(for: match, in: line, pattern: pattern, replacement: replacement)
}
