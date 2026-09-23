import AemiKernel
import Foundation

/// The text that replaces `match` in `line`: `replacement` itself for a literal pattern, and for a regular expression
/// the template expanded from the expression's match at the same columns of `line`, so a lookaround or a boundary at
/// the match's edge sees the whole line, as it did during the search.
/// - Returns: nil when the expression no longer matches exactly those columns, or runs out of its budget; the caller
///   leaves that match as it is rather than write an unexpanded template.
public func buildReplacement(
    for match: SearchMatch,
    in line: String,
    pattern: SearchPattern,
    replacement: String
) -> String? {
    let deadline = ContinuousClock.now.advanced(by: RegexMatcher.fileBudget)
    // One text per match asked for.
    return replacements(for: [match], in: line, pattern: pattern, template: replacement, deadline: deadline)[0]
}

/// Replaces `matches` in `lines`. Every replacement is expanded from the line as it was searched, so a lookaround that
/// reaches a neighbouring match sees the original text, not that match's replacement.
/// - Returns: The new lines and how many matches were replaced. A match whose replacement cannot be expanded, that
///   overlaps a replaced one or that lies outside its line is left as it is and not counted.
public func applyReplacements(
    to lines: [String],
    matches: [SearchMatch],
    pattern: SearchPattern,
    replacement: String
) -> (newLines: [String], replacementCount: Int) {
    var result = lines
    var count = 0
    // One budget for the file, as the search had: a per-line budget lets a backtracking pattern spend it on every line.
    let deadline = ContinuousClock.now.advanced(by: RegexMatcher.fileBudget)
    let ordered = matches.sorted { ($0.row, $0.colStart, $0.colEnd) < ($1.row, $1.colStart, $1.colEnd) }
    var start = 0
    while start < ordered.count {
        let row = ordered[start].row
        var end = start + 1
        while end < ordered.count, ordered[end].row == row { end += 1 }
        if row >= 0, row < lines.count {
            let replaced = rewritten(
                lines[row], replacing: ordered[start ..< end], pattern: pattern, template: replacement,
                deadline: deadline)
            result[row] = replaced.line
            count += replaced.count
        }
        start = end
    }
    return (result, count)
}

/// `line` with `matches`, sorted by column, replaced in one pass from its start, and how many were replaced.
private func rewritten(
    _ line: String, replacing matches: ArraySlice<SearchMatch>, pattern: SearchPattern, template: String,
    deadline: ContinuousClock.Instant
) -> (line: String, count: Int) {
    let texts = replacements(for: matches, in: line, pattern: pattern, template: template, deadline: deadline)
    var rebuilt = ""
    var count = 0
    // Everything before `copied` is in `rebuilt`; `copiedColumn` is its column.
    var copied = line.startIndex
    var copiedColumn = 0
    var previous: SearchMatch?
    for (match, text) in zip(matches, texts) {
        guard let text, match != previous, match.colStart >= copiedColumn, match.colEnd >= match.colStart,
            let start = line.index(copied, offsetBy: match.colStart - copiedColumn, limitedBy: line.endIndex),
            let end = line.index(start, offsetBy: match.colEnd - match.colStart, limitedBy: line.endIndex)
        else { continue }
        rebuilt += line[copied ..< start]
        rebuilt += text
        copied = end
        copiedColumn = match.colEnd
        previous = match
        count += 1
    }
    rebuilt += line[copied...]
    return (rebuilt, count)
}

/// The replacement for each of `matches`, sorted by column on one line: `template` itself for a literal pattern;
/// for a regular expression, `template` expanded from the expression's match that starts and ends at the same columns
/// of `line`, or nil when it has none there or the budget runs out first.
private func replacements(
    for matches: some Collection<SearchMatch>, in line: String, pattern: SearchPattern, template: String,
    deadline: ContinuousClock.Instant
) -> [String?] {
    guard case .regex(let regex) = pattern else { return matches.map { _ in template } }
    let wanted = Array(matches)
    var texts = [String?](repeating: nil, count: wanted.count)
    var next = 0
    // Columns are counted as `findMatches` counts them: in characters, skipping a match that splits one.
    var cursor = line.startIndex
    var cursorColumn = 0
    RegexMatcher.enumerate(regex.expression, in: line, deadline: deadline) { found in
        guard let range = Range(found.range, in: line),
            range.lowerBound.samePosition(in: line) != nil,
            range.upperBound.samePosition(in: line) != nil,
            range.lowerBound >= cursor
        else { return true }
        let colStart = cursorColumn + line.distance(from: cursor, to: range.lowerBound)
        let colEnd = colStart + line.distance(from: range.lowerBound, to: range.upperBound)
        cursor = range.upperBound
        cursorColumn = colEnd
        while next < wanted.count, wanted[next].colStart < colStart { next += 1 }
        while next < wanted.count, wanted[next].colStart == colStart {
            if wanted[next].colEnd == colEnd {
                texts[next] = expandReplacementTemplate(template, using: found, in: line)
            }
            next += 1
        }
        return next < wanted.count
    }
    return texts
}

private func captureGroup(at index: Int, in match: NSTextCheckingResult, text: String) -> String? {
    guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else {
        return nil
    }
    return String(text[range])
}

/// Expands `$N` references and `$$` escapes in a replacement template.
///
/// - `$$` produces a literal `$`.
/// - `$N` (where `N` is one or more digits) produces the value of capture group `N`,
///   with `$0` being the full match. The longest valid prefix is preferred:
///   given `$12` with 5 capture groups, the result is `<group 1>` followed by `"2"`.
/// - A trailing `$` or `$` followed by a non-digit, non-`$` character is emitted literally.
private func expandReplacementTemplate(
    _ template: String, using match: NSTextCheckingResult, in text: String
) -> String {
    let groupCount = match.numberOfRanges
    var result = ""
    result.reserveCapacity(template.count)

    var index = template.startIndex
    while index < template.endIndex {
        let char = template[index]
        if char != "$" {
            result.append(char)
            index = template.index(after: index)
            continue
        }

        let afterDollar = template.index(after: index)
        guard afterDollar < template.endIndex else {
            result.append("$")
            index = afterDollar
            continue
        }

        let next = template[afterDollar]
        if next == "$" {
            result.append("$")
            index = template.index(after: afterDollar)
            continue
        }

        guard let nextByte = next.asciiValue, ASCII.isDigit(nextByte) else {
            result.append("$")
            index = afterDollar
            continue
        }

        // Consume consecutive digits, then back off to the longest index that
        // matches an existing capture group.
        var scan = afterDollar
        var digits = ""
        while scan < template.endIndex, let digit = template[scan].asciiValue,
            ASCII.isDigit(digit)
        {
            digits.append(template[scan])
            scan = template.index(after: scan)
        }

        var consumed = digits.count
        var resolved: String? = nil
        while consumed > 0 {
            let candidate = String(digits.prefix(consumed))
            if let groupIndex = Int(candidate), groupIndex < groupCount {
                resolved = captureGroup(at: groupIndex, in: match, text: text) ?? ""
                break
            }
            consumed -= 1
        }

        if let resolved {
            result.append(resolved)
            // Advance past the digits we consumed.
            index = template.index(afterDollar, offsetBy: consumed)
            // Append any leftover digits as literals.
            if consumed < digits.count {
                result.append(contentsOf: digits.suffix(digits.count - consumed))
                index = scan
            }
        } else {
            // No valid index even for "$0" — emit "$" and the digits literally.
            result.append("$")
            result.append(contentsOf: digits)
            index = scan
        }
    }

    return result
}
