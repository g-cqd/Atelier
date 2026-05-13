import Foundation

// SAFETY: Regex<AnyRegexOutput> is not yet declared Sendable in Swift stdlib, but
// once compiled, a Regex is immutable and the backing storage is internally safe
// to share across concurrency domains.
public enum SearchPattern: @unchecked Sendable {
    case literal(text: String, caseSensitive: Bool)
    case regex(Regex<AnyRegexOutput>)
}

public func compilePattern(_ query: SearchQuery) -> SearchPattern? {
    guard !query.text.isEmpty else { return nil }

    func applyCaseOption(_ regex: Regex<AnyRegexOutput>) -> Regex<AnyRegexOutput> {
        query.isCaseSensitive ? regex : regex.ignoresCase()
    }

    if query.isRegex {
        // Wrap user pattern in a non-capturing group so whole-word anchoring
        // applies to the entire alternation. `Regex.ignoresCase()` replaces
        // ad-hoc `(?i)` prefixing.
        let patternText = query.wholeWord ? "\\b(?:\(query.text))\\b" : query.text
        guard let regex = try? Regex(patternText) else { return nil }
        return .regex(applyCaseOption(regex))
    } else {
        if query.wholeWord {
            let escaped = NSRegularExpression.escapedPattern(for: query.text)
            guard let regex = try? Regex("\\b\(escaped)\\b") else { return nil }
            return .regex(applyCaseOption(regex))
        }
        return .literal(text: query.text, caseSensitive: query.isCaseSensitive)
    }
}
