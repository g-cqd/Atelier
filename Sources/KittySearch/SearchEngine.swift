import Foundation

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
            while searchStart < line.endIndex,
                let range = line.range(
                    of: text, options: options, range: searchStart..<line.endIndex)
            {
                let colStart = line.distance(from: line.startIndex, to: range.lowerBound)
                let colEnd = line.distance(from: line.startIndex, to: range.upperBound)
                matches.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
                searchStart = range.upperBound
            }
        }

    case .regex(let regex):
        for (row, line) in lines.enumerated() {
            // Same rationale as the literal branch. Regex pathologies
            // (catastrophic backtracking on a long line) are the real
            // reason this matters — pre-req for NF24 ReDoS mitigation.
            if Task.isCancelled { return matches }
            for match in line.matches(of: regex) {
                let colStart = line.distance(from: line.startIndex, to: match.range.lowerBound)
                let colEnd = line.distance(from: line.startIndex, to: match.range.upperBound)
                matches.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
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

    return lines[start...end].joined(separator: "\n")
}
