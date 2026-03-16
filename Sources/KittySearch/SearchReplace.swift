import Foundation

public func buildReplacement(
    for match: SearchMatch,
    in line: String,
    pattern: SearchPattern,
    replacement: String
) -> String {
    switch pattern {
    case .literal:
        return replacement

    case .regex(let regex):
        // Support capture group substitution ($1, $2, etc.)
        let chars = Array(line)
        guard match.colStart >= 0, match.colEnd <= chars.count else { return replacement }
        let matchStr = String(chars[match.colStart..<match.colEnd])

        guard let regexMatch = matchStr.wholeMatch(of: regex) else {
            return replacement
        }

        var result = replacement
        // Replace $0 with full match
        result = result.replacingOccurrences(of: "$0", with: String(regexMatch.0))

        // Replace $1..$9 with capture groups
        for i in 1...9 {
            let placeholder = "$\(i)"
            guard result.contains(placeholder) else { continue }
            if let value = captureGroup(at: i, in: regexMatch) {
                result = result.replacingOccurrences(of: placeholder, with: value)
            }
        }

        return result
    }
}

public func applyReplacements(
    to lines: [String],
    matches: [SearchMatch],
    pattern: SearchPattern,
    replacement: String
) -> (newLines: [String], replacementCount: Int) {
    var result = lines
    var count = 0

    // Apply in reverse order to preserve positions
    for match in matches.reversed() {
        guard match.row >= 0, match.row < result.count else { continue }
        let line = result[match.row]
        let replacementText = buildReplacement(
            for: match, in: line, pattern: pattern, replacement: replacement)

        let chars = Array(line)
        guard match.colStart >= 0, match.colEnd <= chars.count else { continue }
        let before = String(chars.prefix(match.colStart))
        let after = String(chars.suffix(from: chars.index(chars.startIndex, offsetBy: match.colEnd)))
        result[match.row] = before + replacementText + after
        count += 1
    }

    return (result, count)
}

private func captureGroup(at index: Int, in match: Regex<AnyRegexOutput>.Match) -> String? {
    let output = match.output
    guard index < output.count else { return nil }
    guard let substring = output[index].substring else { return nil }
    return String(substring)
}
