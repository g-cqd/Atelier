import Foundation
import Synchronization

// SAFETY: Regex<AnyRegexOutput> is not yet declared Sendable in Swift stdlib, but
// once compiled, a Regex is immutable and the backing storage is internally safe
// to share across concurrency domains.
public enum SearchPattern: @unchecked Sendable {
    case literal(text: String, caseSensitive: Bool)
    case regex(Regex<AnyRegexOutput>)
}

public func compilePattern(_ query: SearchQuery) -> SearchPattern? {
    guard !query.text.isEmpty else { return nil }
    return SearchPatternCache.shared.pattern(for: query)
}

/// Audit A7 — `compilePattern` used to allocate a fresh `Regex<AnyRegexOutput>`
/// for every find-field keystroke. A 20-character regex query paid 20 compile
/// passes on the way in. This cache keeps the most recent compilations
/// keyed by `(text, isRegex, isCaseSensitive, wholeWord)`. LRU 4 entries
/// is small enough that the dictionary lookup stays cheap and large enough
/// to cover the realistic "user types, deletes, retypes" pattern.
private final class SearchPatternCache: Sendable {
    static let shared = SearchPatternCache()

    private struct Key: Hashable, Sendable {
        let text: String
        let isRegex: Bool
        let isCaseSensitive: Bool
        let wholeWord: Bool
    }

    private struct State {
        var entries: [Key: SearchPattern] = [:]
        var insertionOrder: [Key] = []
        static let maxEntries = 4
    }

    private let storage = Mutex(State())

    /// Returns the cached `SearchPattern` for `query`, compiling on miss.
    /// `nil` if the regex doesn't compile (cached as absent? no — only
    /// successful compilations live in the cache so a typo doesn't pin
    /// a negative entry).
    func pattern(for query: SearchQuery) -> SearchPattern? {
        let key = Key(
            text: query.text,
            isRegex: query.isRegex,
            isCaseSensitive: query.isCaseSensitive,
            wholeWord: query.wholeWord)
        if let hit = storage.withLock({ $0.entries[key] }) {
            return hit
        }
        guard let compiled = SearchPatternCache.compile(query) else { return nil }
        storage.withLock { state in
            // Recheck on insert in case another worker filled the slot
            // between our miss and this insert. First-writer-wins; an
            // identical compile is harmless.
            if state.entries[key] == nil {
                if state.entries.count >= State.maxEntries,
                    !state.insertionOrder.isEmpty
                {
                    let oldest = state.insertionOrder.removeFirst()
                    state.entries.removeValue(forKey: oldest)
                }
                state.entries[key] = compiled
                state.insertionOrder.append(key)
            }
        }
        return compiled
    }

    private static func compile(_ query: SearchQuery) -> SearchPattern? {
        func applyCaseOption(_ regex: Regex<AnyRegexOutput>) -> Regex<AnyRegexOutput> {
            query.isCaseSensitive ? regex : regex.ignoresCase()
        }

        if query.isRegex {
            // Wrap user pattern in a non-capturing group so whole-word
            // anchoring applies to the entire alternation.
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
}
