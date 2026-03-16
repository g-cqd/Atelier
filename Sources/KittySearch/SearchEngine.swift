import Foundation

public func findMatches(in lines: [String], pattern: SearchPattern) -> [SearchMatch] {
    var matches: [SearchMatch] = []

    switch pattern {
    case .literal(let text, let caseSensitive):
        let options: String.CompareOptions = caseSensitive ? [] : .caseInsensitive
        for (row, line) in lines.enumerated() {
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
