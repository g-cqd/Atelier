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
            // Support capture group substitution ($0..$N) with proper handling
            // for multi-digit indices and a literal `$$` escape.
            let chars = Array(line)
            guard match.colStart >= 0, match.colEnd <= chars.count else { return replacement }
            let matchStr = String(chars[match.colStart ..< match.colEnd])

            var result = replacement
            RegexMatcher.enumerate(regex.wholeExpression, in: matchStr) { regexMatch in
                result = expandReplacementTemplate(replacement, using: regexMatch, in: matchStr)
                return false
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
        let after = String(
            chars.suffix(from: chars.index(chars.startIndex, offsetBy: match.colEnd)))
        result[match.row] = before + replacementText + after
        count += 1
    }

    return (result, count)
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

        guard next.isASCII, next.isNumber else {
            result.append("$")
            index = afterDollar
            continue
        }

        // Consume consecutive digits, then back off to the longest index that
        // matches an existing capture group.
        var scan = afterDollar
        var digits = ""
        while scan < template.endIndex, let digit = template[scan].asciiValue,
            digit >= 0x30, digit <= 0x39
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
