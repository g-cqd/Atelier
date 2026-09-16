import Foundation
import KittyCodecs
public import KittyRenderer
import KittySearch
public import KittyWidgets

@MainActor
public func renderSearchPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    guard rect.width > 0, rect.height > 0 else { return nil }

    let bgCell = Cell(character: " ", style: colorScheme.treeBg)
    pipeline.buffer.fill(
        row: rect.y, col: rect.x, width: rect.width, height: rect.height, cell: bgCell)

    let maxCol = rect.x + rect.width
    var currentRow = rect.y
    var cursorPosition: (row: Int, col: Int)?

    // Row 0: Header with scope indicator
    let scopeLabel = state.searchTarget == .workspace ? "SEARCH (WORKSPACE)" : "SEARCH"
    pipeline.buffer.write(scopeLabel, row: currentRow, col: rect.x + 1, style: colorScheme.lineNumber)
    currentRow += 1

    // Row 1: Query input field
    if currentRow < rect.y + rect.height {
        let query = state.inFileSearch?.query ?? ""
        let prefix = "> "
        let availWidth = max(0, rect.width - prefix.count - 1)
        let displayQuery = String(query.suffix(availWidth))
        pipeline.buffer.write(prefix, row: currentRow, col: rect.x, style: colorScheme.treeBg)
        pipeline.buffer.write(
            displayQuery, row: currentRow, col: rect.x + prefix.count,
            style: colorScheme.editorText)

        if state.mode == .searchPanel, state.searchPanelFocus == .findField {
            let displayLen = min(query.count, availWidth)
            let cursorCol = rect.x + prefix.count + displayLen
            cursorPosition = (row: currentRow, col: min(cursorCol, maxCol - 1))
        }
        currentRow += 1
    }

    // Row 2 (optional): Replace input field
    if state.inFileSearch?.showReplace == true, currentRow < rect.y + rect.height {
        let replaceText = state.inFileSearch?.replaceText ?? ""
        let prefix = "↳ "
        let availWidth = max(0, rect.width - prefix.count - 1)
        let displayText = String(replaceText.suffix(availWidth))
        pipeline.buffer.write(prefix, row: currentRow, col: rect.x, style: colorScheme.treeBg)
        pipeline.buffer.write(
            displayText, row: currentRow, col: rect.x + prefix.count,
            style: colorScheme.editorText)

        if state.mode == .searchPanel, state.searchPanelFocus == .replaceField {
            let displayLen = min(replaceText.count, availWidth)
            let cursorCol = rect.x + prefix.count + displayLen
            cursorPosition = (row: currentRow, col: min(cursorCol, maxCol - 1))
        }
        currentRow += 1
    }

    // Toggle indicators
    if currentRow < rect.y + rect.height {
        let caseSensitive = state.inFileSearch?.isCaseSensitive ?? false
        let isRegex = state.inFileSearch?.isRegex ?? false
        let aaLabel = caseSensitive ? "[Aa]" : " Aa "
        let reLabel = isRegex ? "[.*]" : " .* "
        let scopeLabel = state.searchTarget == .workspace ? "[WS]" : "[F] "
        pipeline.buffer.write(
            aaLabel, row: currentRow, col: rect.x + 1, style: colorScheme.lineNumber)
        pipeline.buffer.write(
            reLabel, row: currentRow, col: rect.x + 6, style: colorScheme.lineNumber)
        pipeline.buffer.write(
            scopeLabel, row: currentRow, col: rect.x + 11, style: colorScheme.lineNumber)
        currentRow += 1
    }

    // Summary line
    if currentRow < rect.y + rect.height {
        let summary: String
        if state.searchTarget == .workspace {
            summary = state.workspaceSearchSummary
        } else {
            let matchCount = state.inFileSearch?.matches.count ?? 0
            let query = state.inFileSearch?.query ?? ""
            if query.isEmpty {
                summary = ""
            } else if matchCount == 0 {
                summary = "No results"
            } else if matchCount == 1 {
                summary = "1 match"
            } else {
                summary = "\(matchCount) matches"
            }
        }
        pipeline.buffer.write(
            summary, row: currentRow, col: rect.x + 1,
            style: colorScheme.lineNumber)
        currentRow += 1
    }

    // Results
    let resultsStartRow = currentRow
    let availRows = max(0, rect.y + rect.height - resultsStartRow)

    if availRows > 0 {
        if state.searchTarget == .workspace {
            renderWorkspaceResults(
                pipeline: pipeline, state: state, rect: rect,
                startRow: resultsStartRow, availRows: availRows,
                colorScheme: colorScheme)
        } else {
            renderInFileResults(
                pipeline: pipeline, state: state, rect: rect,
                startRow: resultsStartRow, availRows: availRows,
                colorScheme: colorScheme)
        }
    }

    return cursorPosition
}

@MainActor
private func renderInFileResults(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    startRow: Int,
    availRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    guard let search = state.inFileSearch, !search.matches.isEmpty else { return }

    let scrollOffset = state.searchPanelScrollOffset
    let matches = search.matches
    let lines = state.fileContent

    for i in 0..<availRows {
        let matchIdx = scrollOffset + i
        guard matchIdx < matches.count else { break }

        let match = matches[matchIdx]
        let displayRow = startRow + i

        let lineNum = "\(match.row + 1):"
        let snippet: String
        if match.row >= 0, match.row < lines.count {
            let line = lines[match.row]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let snippetWidth = max(0, rect.width - lineNum.count - 2)
            snippet = String(trimmed.prefix(snippetWidth))
        } else {
            snippet = ""
        }

        let isSelected = state.searchPanelFocus == .resultsList
            && matchIdx == state.searchPanelSelectedIndex
        let isActive = matchIdx == search.activeMatchIndex
        let rowStyle: Style
        if isSelected {
            rowStyle = colorScheme.treeSelected
        } else if isActive {
            rowStyle = colorScheme.activeSearchMatch
        } else {
            rowStyle = colorScheme.treeBg
        }

        if isSelected || isActive {
            let rowBgCell = Cell(character: " ", style: rowStyle)
            pipeline.buffer.fill(
                row: displayRow, col: rect.x, width: rect.width, height: 1, cell: rowBgCell)
        }

        pipeline.buffer.write(
            lineNum, row: displayRow, col: rect.x + 1, style: colorScheme.lineNumber)

        let snippetCol = rect.x + 1 + lineNum.count
        pipeline.buffer.write(snippet, row: displayRow, col: snippetCol, style: rowStyle)

        // Highlight the matched text span within the snippet
        if match.row >= 0, match.row < lines.count {
            let line = lines[match.row]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let leadingWhitespace = line.count - trimmed.count
            let matchStartInSnippet = max(0, match.colStart - leadingWhitespace)
            let matchEndInSnippet = max(0, match.colEnd - leadingWhitespace)
            let snippetWidth = max(0, rect.width - lineNum.count - 2)
            if matchStartInSnippet < snippetWidth, matchEndInSnippet > 0 {
                let highlightStart = max(0, matchStartInSnippet)
                let highlightEnd = min(snippetWidth, matchEndInSnippet)
                if highlightStart < highlightEnd {
                    let matchStyle = isActive ? colorScheme.activeSearchMatch : colorScheme.searchMatch
                    let chars = Array(trimmed)
                    let startIdx = min(highlightStart, chars.count)
                    let endIdx = min(highlightEnd, chars.count)
                    let matchText = String(chars[startIdx..<endIdx])
                    pipeline.buffer.write(
                        matchText, row: displayRow, col: snippetCol + highlightStart, style: matchStyle)
                }
            }
        }
    }
}

@MainActor
private func renderWorkspaceResults(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    startRow: Int,
    availRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    guard !state.workspaceSearchResults.isEmpty else {
        if state.isSearchingWorkspace {
            pipeline.buffer.write(
                "Searching...", row: startRow, col: rect.x + 1, style: colorScheme.lineNumber)
        }
        return
    }

    let scrollOffset = state.searchPanelScrollOffset
    var flatIndex = 0
    var displayedRows = 0

    for fileResult in state.workspaceSearchResults {
        guard displayedRows < availRows else { break }

        // File header row
        if flatIndex >= scrollOffset {
            let displayRow = startRow + displayedRows
            let headerText = "\(fileResult.fileName) (\(fileResult.matches.count))"
            let isSelected = state.searchPanelFocus == .resultsList
                && flatIndex == state.searchPanelSelectedIndex
            let headerStyle = isSelected ? colorScheme.treeSelected : colorScheme.treeDir
            if isSelected {
                let rowBgCell = Cell(character: " ", style: headerStyle)
                pipeline.buffer.fill(
                    row: displayRow, col: rect.x, width: rect.width, height: 1, cell: rowBgCell)
            }
            pipeline.buffer.write(
                headerText, row: displayRow, col: rect.x + 1, style: headerStyle)
            displayedRows += 1
        }
        flatIndex += 1

        // Match rows
        for match in fileResult.matches {
            guard displayedRows < availRows else { break }
            if flatIndex >= scrollOffset {
                let displayRow = startRow + displayedRows
                let lineNum = "  \(match.row + 1):"
                let snippetIdx = match.row
                let snippet: String
                if snippetIdx >= 0, snippetIdx < fileResult.contextSnippets.count {
                    let snippetWidth = max(0, rect.width - lineNum.count - 2)
                    snippet = String(fileResult.contextSnippets[snippetIdx].prefix(snippetWidth))
                } else {
                    snippet = ""
                }

                let isSelected = state.searchPanelFocus == .resultsList
                    && flatIndex == state.searchPanelSelectedIndex
                let rowStyle = isSelected ? colorScheme.treeSelected : colorScheme.treeBg

                if isSelected {
                    let rowBgCell = Cell(character: " ", style: rowStyle)
                    pipeline.buffer.fill(
                        row: displayRow, col: rect.x, width: rect.width, height: 1, cell: rowBgCell)
                }

                let snippetCol = rect.x + 1 + lineNum.count
                pipeline.buffer.write(
                    lineNum, row: displayRow, col: rect.x + 1, style: colorScheme.lineNumber)
                pipeline.buffer.write(snippet, row: displayRow, col: snippetCol, style: rowStyle)

                // Highlight matched span within snippet
                if snippetIdx >= 0, snippetIdx < fileResult.contextSnippets.count {
                    let snippetText = fileResult.contextSnippets[snippetIdx]
                    let trimmed = snippetText.trimmingCharacters(in: .whitespaces)
                    let leadingWS = snippetText.count - trimmed.count
                    let snippetWidth = max(0, rect.width - lineNum.count - 2)
                    let mStart = max(0, match.colStart - leadingWS)
                    let mEnd = max(0, match.colEnd - leadingWS)
                    if mStart < snippetWidth, mEnd > 0 {
                        let hStart = max(0, mStart)
                        let hEnd = min(snippetWidth, mEnd)
                        if hStart < hEnd {
                            let matchStyle = isSelected
                                ? colorScheme.activeSearchMatch : colorScheme.searchMatch
                            let chars = Array(trimmed)
                            let sIdx = min(hStart, chars.count)
                            let eIdx = min(hEnd, chars.count)
                            let matchText = String(chars[sIdx..<eIdx])
                            pipeline.buffer.write(
                                matchText, row: displayRow, col: snippetCol + hStart,
                                style: matchStyle)
                        }
                    }
                }
                displayedRows += 1
            }
            flatIndex += 1
        }
    }
}
