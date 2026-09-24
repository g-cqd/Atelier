import AemiCore
import AtelierText
import Foundation
// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable file_length
import KittyApp
public import KittyCodecs
import KittyInput
public import KittyRenderer
public import KittySearch
import KittyWorkspace

import class AemiRuntime.BlockingOffloadPool

public enum SearchStepDirection {
    case next
    case previous
}

@MainActor
public func openInFileSearch(state: EditorState) {
    var prefill = ""
    if let selection = state.selection, !selection.isCollapsed {
        let (start, end) = selection.ordered
        if start.row == end.row {
            let line = state.fileLine(at: start.row)
            let startIdx = line.index(line.startIndex, offsetBy: min(start.col, line.count))
            let endIdx = line.index(line.startIndex, offsetBy: min(end.col, line.count))
            if startIdx < endIdx {
                prefill = String(line[startIdx ..< endIdx])
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
        scheduleInFileSearch(&search, state: state, pipeline: nil)
    }

    state.inFileSearch = search
}

@MainActor
public func handleSearchKey(
    _ key: KeyEvent, state: EditorState, pipeline: RenderPipeline
) -> Bool {
    switch key.keyCode {
        case AsciiKey.escape:
            cancelInFileSearch(state: state)
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
                cancelInFileSearch(state: state)
                state.inFileSearch = nil
            } else {
                search.query.removeLast()
                scheduleInFileSearch(&search, state: state, pipeline: pipeline)
                state.inFileSearch = search
            }
            return true

        default:
            guard let text = textInsertion(for: key, allowTab: false) else { return true }
            guard var search = state.inFileSearch else { return true }
            search.query.append(text)
            scheduleInFileSearch(&search, state: state, pipeline: pipeline)
            state.inFileSearch = search
            return true
    }
}

@MainActor
public func stepSearchMatch(
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
public func jumpToMatch(
    _ match: SearchMatch, state: EditorState, pipeline: RenderPipeline
) {
    state.cursorRow = match.row
    state.cursorCol = match.colStart
    ensureEditorVisibleFull(state: state, pipeline: pipeline)
}

public func executeSearch(
    _ search: inout EditorState.InFileSearch, lines: [String], maxMatches: Int = 10_000
) {
    let query = SearchQuery(
        text: search.query,
        isCaseSensitive: search.isCaseSensitive,
        isRegex: search.isRegex,
        wholeWord: search.isWholeWord
    )
    search.pattern = compilePattern(query)
    if let pattern = search.pattern {
        let scan = scanMatches(in: lines, pattern: pattern, maxMatches: maxMatches)
        search.matches = scan.matches
        search.isComplete = scan.isComplete
        search.didHitLimit = scan.didHitLimit
    } else {
        search.matches = []
        search.isComplete = false
        search.didHitLimit = false
    }
    search.isSearching = false
}

struct InFileSearchRequest: Sendable, Equatable {
    let query: SearchQuery
    let bufferID: ObjectIdentifier?
    let documentVersion: Int
    let contentHash: Int
}

@MainActor
// Track 3B will move these jobs into editor state alongside the other background state.
private enum InFileSearchJobs {
    struct Job {
        let generation: UInt64
        let task: Task<Void, Never>
    }
    static var nextGeneration: UInt64 = 0
    static var jobs: [ObjectIdentifier: Job] = [:]
}

@MainActor
func cancelInFileSearch(state: EditorState) {
    InFileSearchJobs.jobs.removeValue(forKey: ObjectIdentifier(state))?.task.cancel()
}

/// Starts the current query on the blocking search pool and leaves only its query visible until the result arrives.
@MainActor
func scheduleInFileSearch(
    _ search: inout EditorState.InFileSearch, state: EditorState, pipeline: RenderPipeline?,
    advanceToNext: Bool = false, moveCursorOnCompletion: Bool = true
) {
    cancelInFileSearch(state: state)
    search.pattern = nil
    search.matches = []
    search.activeMatchIndex = -1
    search.isSearching = false
    search.isComplete = false
    search.didHitLimit = false
    search.resultRequest = nil
    let query = SearchQuery(
        text: search.query, isCaseSensitive: search.isCaseSensitive, isRegex: search.isRegex,
        wholeWord: search.isWholeWord)
    guard !query.text.isEmpty else { return }
    search.isSearching = true

    let rope = state.textBuffer.ropeSnapshot
    let request = InFileSearchRequest(
        query: query, bufferID: state.bufferManager.activeBuffer.map(ObjectIdentifier.init),
        documentVersion: state.bufferManager.activeBuffer?.documentVersion ?? 0,
        contentHash: rope.contentHash)
    let maxMatches = max(0, state.config.search.maxResults)
    let pool = state.searchPool
    let id = ObjectIdentifier(state)
    InFileSearchJobs.nextGeneration &+= 1
    let generation = InFileSearchJobs.nextGeneration
    let task = state.taskProvider.task(role: .work) { @MainActor [weak state] in
        defer {
            if InFileSearchJobs.jobs[id]?.generation == generation { InFileSearchJobs.jobs[id] = nil }
        }
        let result = await runInFileSearch(query: query, rope: rope, maxMatches: maxMatches, pool: pool)
        guard let state, !Task.isCancelled,
            InFileSearchJobs.jobs[id]?.generation == generation
        else { return }
        _ = applyInFileSearchResult(
            state: state, request: request, pattern: result.0, scan: result.1, pipeline: pipeline,
            advanceToNext: advanceToNext, moveCursorOnCompletion: moveCursorOnCompletion)
    }
    InFileSearchJobs.jobs[id] = .init(generation: generation, task: task)
}

private func runInFileSearch(
    query: SearchQuery, rope: Rope, maxMatches: Int, pool: BlockingOffloadPool
) async -> (SearchPattern?, SearchScanResult) {
    await withTaskExecutorPreference(pool) {
        let pattern = compilePattern(query)
        let scan =
            pattern.map { scanMatches(in: rope.allLines, pattern: $0, maxMatches: maxMatches) }
            ?? SearchScanResult(matches: [], isComplete: false, didHitLimit: false)
        return (pattern, scan)
    }
}

@MainActor
@discardableResult
func applyInFileSearchResult(
    state: EditorState, request: InFileSearchRequest, pattern: SearchPattern?, scan: SearchScanResult,
    pipeline: RenderPipeline?,
    advanceToNext: Bool = false, moveCursorOnCompletion: Bool = true
) -> Bool {
    guard state.bufferManager.activeBuffer.map(ObjectIdentifier.init) == request.bufferID,
        (state.bufferManager.activeBuffer?.documentVersion ?? 0) == request.documentVersion,
        state.textBuffer.contentHash == request.contentHash,
        var search = state.inFileSearch,
        SearchQuery(
            text: search.query, isCaseSensitive: search.isCaseSensitive, isRegex: search.isRegex,
            wholeWord: search.isWholeWord) == request.query
    else { return false }
    search.pattern = pattern
    search.matches = scan.matches
    search.isSearching = false
    search.isComplete = scan.isComplete
    search.didHitLimit = scan.didHitLimit
    search.resultRequest = request
    let nearest = nearestMatchIndex(from: state.cursorRow, col: state.cursorCol, in: scan.matches)
    search.activeMatchIndex = advanceToNext && !scan.matches.isEmpty ? (nearest + 1) % scan.matches.count : nearest
    state.inFileSearch = search
    if moveCursorOnCompletion, let pipeline, let match = search.activeMatch {
        jumpToMatch(match, state: state, pipeline: pipeline)
    }
    state.renderRefreshSource?.invalidate()
    return true
}

public func nearestMatchIndex(
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
public func handleSearchPanelKey(
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
            cancelInFileSearch(state: state)
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
                scheduleInFileSearch(&search, state: state, pipeline: pipeline)
                state.inFileSearch = search
                state.searchPanelScrollOffset = 0
                if state.searchTarget == .workspace {
                    triggerWorkspaceSearchDebounced(state: state)
                }
            }
            return true

        default:
            guard let text = textInsertion(for: key, allowTab: false) else { return true }
            guard var search = state.inFileSearch else { return true }
            search.query.append(text)
            scheduleInFileSearch(&search, state: state, pipeline: pipeline)
            state.inFileSearch = search
            state.searchPanelScrollOffset = 0
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
            scheduleInFileSearch(&search, state: state, pipeline: pipeline)
            state.inFileSearch = search
            state.searchPanelScrollOffset = 0
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
            scheduleInFileSearch(&search, state: state, pipeline: pipeline)
            state.inFileSearch = search
            state.searchPanelScrollOffset = 0
            triggerWorkspaceSearchDebounced(state: state)
            return true
    }
}

// MARK: - Search scroll visibility

@MainActor
public func ensureSearchResultVisible(state: EditorState) {
    let idx = state.searchPanelSelectedIndex
    guard idx >= 0 else { return }

    // An estimate from the last render size and about five header rows; the real viewport is `availRows` in
    // `renderSearchPanel`.
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
public func workspaceFlatResultCount(state: EditorState) -> Int {
    var count = 0
    for fileResult in state.workspaceSearchResults {
        count += 1  // file header
        count += fileResult.matches.count
    }
    return count
}

@MainActor
public func workspaceFlatResult(
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
public func openWorkspaceSearchResult(
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
public func triggerWorkspaceSearch(state: EditorState) {
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
    guard compilePattern(query) != nil else {
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

    // Retain persistent snapshots; line materialization runs on the search pool.
    var openRopes: [String: Rope] = [:]
    for buffer in state.bufferManager.buffers where !buffer.filePath.isEmpty {
        openRopes[buffer.filePath] = buffer.textBuffer.ropeSnapshot
    }
    let ropeSnapshots = openRopes

    let rootPath = state.rootPath
    let maxResults = state.config.search.maxResults
    let taskProvider = state.taskProvider
    let searchPool = state.searchPool

    state.workspaceSearchTask = taskProvider.task(role: .work) { @MainActor in
        // The walk blocks on the file system, so it runs on the pool, off the main actor and the cooperative pool.
        let files = (try? await searchPool.run { enumerateSearchableFiles(rootPath: rootPath) }) ?? []

        guard !Task.isCancelled else { return }

        if files.isEmpty {
            state.workspaceSearchSummary = "No files to search"
            state.isSearchingWorkspace = false
            state.renderRefreshSource?.invalidate()
            return
        }

        let openBuffers: [String: [String]]
        do {
            openBuffers = try await searchPool.run { ropeSnapshots.mapValues(\.allLines) }
        } catch is CancellationError {
            return
        } catch {
            state.workspaceSearchSummary = "Search failed: \(error.localizedDescription)"
            state.isSearchingWorkspace = false
            return
        }
        guard !Task.isCancelled else { return }

        let result =
            await taskProvider.detachedTask(role: .work) { [openBuffers, searchPool] in
                await searchWorkspace(
                    query: query,
                    files: files,
                    openBuffers: openBuffers,
                    pool: searchPool,
                    maxResults: maxResults,
                    onProgress: { _ in }
                )
            }
            .value

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
public func triggerWorkspaceSearchDebounced(state: EditorState) {
    // Provide immediate UI feedback so the user sees the search panel
    // acknowledged the keystroke even before the debounce window elapses.
    state.isSearchingWorkspace = true
    state.workspaceSearchSummary = "Searching..."
    // `workspaceSearchDebounceTask` debounces the burst into one search.
    state.workspaceSearchDebounceContinuation.yield(())
}

// MARK: - Replace operations

@MainActor
public func replaceCurrentMatch(state: EditorState, pipeline: RenderPipeline) {
    guard let search = state.inFileSearch,
        let match = search.activeMatch,
        !state.readOnly
    else { return }

    guard
        let replacement = buildReplacementText(
            for: match,
            in: state.fileLine(at: match.row),
            pattern: search.pattern,
            replacement: search.replaceText
        )
    else {
        // The text under the match changed since the search, or the expression ran out of time: search again
        // rather than write an unexpanded template.
        reExecuteSearch(state: state, pipeline: pipeline)
        state.statusMessage = "The match changed; nothing replaced"
        return
    }

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
    reExecuteSearch(state: state, pipeline: pipeline, advanceToNext: true)
    state.statusMessage = "Replaced 1 match"
}

@MainActor
public func replaceAllInFile(state: EditorState, pipeline: RenderPipeline) {
    guard let search = state.inFileSearch, !state.readOnly else { return }
    let currentRequest = InFileSearchRequest(
        query: SearchQuery(
            text: search.query, isCaseSensitive: search.isCaseSensitive, isRegex: search.isRegex,
            wholeWord: search.isWholeWord),
        bufferID: state.bufferManager.activeBuffer.map(ObjectIdentifier.init),
        documentVersion: state.bufferManager.activeBuffer?.documentVersion ?? 0,
        contentHash: state.textBuffer.contentHash)
    guard search.isComplete, !search.isSearching, search.resultRequest == currentRequest else {
        state.statusMessage = "Search incomplete or outdated; search again before replacing all"
        return
    }
    guard let pattern = search.pattern, !search.matches.isEmpty else { return }

    let previousSnapshot = state.activeBufferSnapshot()
    // Every replacement is expanded from the lines as they were searched, never from a line already rewritten.
    let (lines, replaceCount) = applyReplacements(
        to: state.fileContent, matches: search.matches, pattern: pattern, replacement: search.replaceText)

    state.fileContent = lines
    state.textDidChange(previousSnapshot: previousSnapshot)

    reExecuteSearch(state: state, pipeline: pipeline)
    state.statusMessage = "Replaced \(replaceCount) occurrences"
}

@MainActor
public func reExecuteSearch(state: EditorState, pipeline: RenderPipeline, advanceToNext: Bool = false) {
    guard var search = state.inFileSearch else { return }
    scheduleInFileSearch(&search, state: state, pipeline: pipeline, advanceToNext: advanceToNext)
    state.inFileSearch = search
    if state.searchTarget == .workspace {
        triggerWorkspaceSearchDebounced(state: state)
    }
}

private func buildReplacementText(
    for match: SearchMatch,
    in line: String,
    pattern: SearchPattern?,
    replacement: String
) -> String? {
    guard let pattern else { return replacement }
    return buildReplacement(for: match, in: line, pattern: pattern, replacement: replacement)
}
