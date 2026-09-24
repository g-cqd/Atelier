import Foundation

/// Matches collected by one scan and whether it examined the entire input.
public struct SearchScanResult: Sendable {
    /// Matches collected before scanning stopped.
    public let matches: [SearchMatch]
    /// Whether the scan examined all input without reaching a limit or being cancelled.
    public let isComplete: Bool
    /// Whether the match cap stopped the scan.
    public let didHitLimit: Bool

    /// Carries both matches and the reason a scan may be incomplete.
    public init(matches: [SearchMatch], isComplete: Bool, didHitLimit: Bool) {
        self.matches = matches
        self.isComplete = isComplete
        self.didHitLimit = didHitLimit
    }
}

/// Returns non-overlapping matches with character-based columns.
/// Regex matches that split an extended grapheme cluster are omitted so replacement cannot
/// corrupt a character. ICU's `\X` matches a complete grapheme cluster.
/// - Complexity: O(scanned text) for a literal; regex work also has a cooperative time budget.
/// - Note: Cancellation, the match cap or the cooperative per-file regex budget returns matches collected so far.
public func findMatches(in lines: [String], pattern: SearchPattern, maxMatches: Int) -> [SearchMatch] {
    scanMatches(in: lines, pattern: pattern, maxMatches: maxMatches).matches
}

/// Scans until the input ends, the cap is reached, cancellation arrives, or a regex exceeds its budget.
/// An incomplete result must not drive a whole-document replacement.
public func scanMatches(in lines: [String], pattern: SearchPattern, maxMatches: Int) -> SearchScanResult {
    let deadline: ContinuousClock.Instant? =
        if case .regex = pattern { ContinuousClock.now.advanced(by: RegexMatcher.fileBudget) } else { nil }
    return scanMatches(in: lines, pattern: pattern, maxMatches: maxMatches, deadline: deadline)
}

/// The deadline seam lets tests exercise expiry without waiting for real time to pass.
func scanMatches(
    in lines: [String], pattern: SearchPattern, maxMatches: Int, deadline: ContinuousClock.Instant?
) -> SearchScanResult {
    guard maxMatches > 0 else {
        return SearchScanResult(matches: [], isComplete: lines.isEmpty, didHitLimit: !lines.isEmpty)
    }
    var matches: [SearchMatch] = []
    matches.reserveCapacity(min(maxMatches, 1_024))

    switch pattern {
        case .literal(let text, let caseSensitive):
            let options: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
            for (row, line) in lines.enumerated() {
                // Checked per line: one pathological line, such as a multi-MB line with many hits, can stall the
                // match loop, and a cancellation should land within a bounded number of lines.
                if Task.isCancelled { return SearchScanResult(matches: matches, isComplete: false, didHitLimit: false) }
                var searchStart = line.startIndex
                // Columns carry forward from the previous match; measuring each from the line start is quadratic in
                // a line with many hits.
                var searchStartColumn = 0
                while searchStart < line.endIndex,
                    let range = line.range(
                        of: text, options: options, range: searchStart ..< line.endIndex)
                {
                    if Task.isCancelled {
                        return SearchScanResult(matches: matches, isComplete: false, didHitLimit: false)
                    }
                    let colStart = searchStartColumn + line.distance(from: searchStart, to: range.lowerBound)
                    let colEnd = colStart + line.distance(from: range.lowerBound, to: range.upperBound)
                    matches.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
                    if matches.count == maxMatches {
                        return SearchScanResult(matches: matches, isComplete: false, didHitLimit: true)
                    }
                    searchStart = range.upperBound
                    searchStartColumn = colEnd
                }
            }

        case .regex(let regex):
            // One budget for the whole file: a per-line budget lets a backtracking pattern spend it on every line.
            guard let deadline else { return SearchScanResult(matches: [], isComplete: false, didHitLimit: false) }
            for (row, line) in lines.enumerated() {
                if Task.isCancelled || ContinuousClock.now >= deadline {
                    return SearchScanResult(matches: matches, isComplete: false, didHitLimit: false)
                }
                var cursor = line.startIndex
                var cursorColumn = 0
                let finishedLine = RegexMatcher.enumerate(regex.expression, in: line, deadline: deadline) { match in
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
                    return matches.count < maxMatches
                }
                if !finishedLine || Task.isCancelled || ContinuousClock.now >= deadline {
                    return SearchScanResult(
                        matches: matches, isComplete: false, didHitLimit: matches.count == maxMatches)
                }
            }
    }

    return SearchScanResult(matches: matches, isComplete: true, didHitLimit: false)
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
