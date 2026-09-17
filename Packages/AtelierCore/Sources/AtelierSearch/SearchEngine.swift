import Foundation

/// Returns non-overlapping matches with character-based columns.
/// Regex matches that split an extended grapheme cluster are omitted so replacement cannot
/// corrupt a character. ICU's `\X` matches a complete grapheme cluster.
/// - Note: Cancellation or the cooperative per-file regex budget returns matches collected so far.
public func findMatches(in lines: [String], pattern: SearchPattern) -> [SearchMatch] {
    var matches: [SearchMatch] = []

    switch pattern {
        case .literal(let text, let caseSensitive):
            let options: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
            for (row, line) in lines.enumerated() {
                // Per-line cancellation check (audit D6). The match loop below
                // can stall on a pathological line (e.g. a multi-MB single line
                // with many literal hits); a parent `Task.cancel` should land
                // within a bounded number of lines, not at task-group boundary.
                if Task.isCancelled { return matches }
                var searchStart = line.startIndex
                // Columns are carried forward from the previous match: measuring each one from the start of the
                // line made a line with many hits quadratic in its length.
                var searchStartColumn = 0
                while searchStart < line.endIndex,
                    let range = line.range(
                        of: text, options: options, range: searchStart ..< line.endIndex)
                {
                    let colStart = searchStartColumn + line.distance(from: searchStart, to: range.lowerBound)
                    let colEnd = colStart + line.distance(from: range.lowerBound, to: range.upperBound)
                    matches.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
                    searchStart = range.upperBound
                    searchStartColumn = colEnd
                }
            }

        case .regex(let regex):
            // One budget for the whole file: a per-line budget let a backtracking pattern spend it on every line.
            let deadline = ContinuousClock.now.advanced(by: RegexMatcher.fileBudget)
            for (row, line) in lines.enumerated() {
                if Task.isCancelled || ContinuousClock.now >= deadline { return matches }
                var cursor = line.startIndex
                var cursorColumn = 0
                RegexMatcher.enumerate(regex.expression, in: line, deadline: deadline) { match in
                    guard let range = Range(match.range, in: line),
                        range.lowerBound.samePosition(in: line) != nil,
                        range.upperBound.samePosition(in: line) != nil,
                        range.lowerBound >= cursor
                    else { return true }
                    let colStart = cursorColumn + line.distance(from: cursor, to: range.lowerBound)
                    let colEnd = colStart + line.distance(from: range.lowerBound, to: range.upperBound)
                    matches.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
                    cursor = range.upperBound
                    cursorColumn = colEnd
                    return true
                }
            }
    }

    return matches
}

public func extractSnippet(
    from lines: [String],
    match: SearchMatch,
    contextLines: Int = 0
) -> String {
    guard !lines.isEmpty, match.row >= 0, match.row < lines.count else { return "" }

    let start = max(0, match.row - contextLines)
    let end = min(lines.count - 1, match.row + contextLines)

    return lines[start ... end].joined(separator: "\n")
}
