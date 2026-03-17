import Foundation

public enum SearchPattern: @unchecked Sendable {
    case literal(text: String, caseSensitive: Bool)
    case regex(Regex<AnyRegexOutput>)
}

public func compilePattern(_ query: SearchQuery) -> SearchPattern? {
    guard !query.text.isEmpty else { return nil }

    if query.isRegex {
        var patternText = query.text
        if query.wholeWord {
            patternText = "\\b(?:\(patternText))\\b"
        }
        if !query.isCaseSensitive {
            patternText = "(?i)" + patternText
        }
        guard let regex = try? Regex(patternText) else { return nil }
        return .regex(regex)
    } else {
        if query.wholeWord {
            let escaped = NSRegularExpression.escapedPattern(for: query.text)
            var patternText = "\\b\(escaped)\\b"
            if !query.isCaseSensitive {
                patternText = "(?i)" + patternText
            }
            guard let regex = try? Regex(patternText) else { return nil }
            return .regex(regex)
        }
        return .literal(text: query.text, caseSensitive: query.isCaseSensitive)
    }
}
