public enum SearchPattern: @unchecked Sendable {
    case literal(text: String, caseSensitive: Bool)
    case regex(Regex<AnyRegexOutput>)
}

public func compilePattern(_ query: SearchQuery) -> SearchPattern? {
    guard !query.text.isEmpty else { return nil }

    if query.isRegex {
        let patternText = query.isCaseSensitive ? query.text : "(?i)" + query.text
        guard let regex = try? Regex(patternText) else { return nil }
        return .regex(regex)
    } else {
        return .literal(text: query.text, caseSensitive: query.isCaseSensitive)
    }
}
