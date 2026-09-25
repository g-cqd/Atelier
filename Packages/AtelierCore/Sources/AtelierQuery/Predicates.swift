import AtelierParser
import Foundation
import Synchronization

/// Evaluates query predicates against captured nodes.
public enum Predicates: Sendable {
    /// Thread-safe regex cache to avoid recompiling patterns.
    private static let regexCache = RegexCache()

    public static func evaluate(
        _ predicate: Predicate,
        captures: [QueryMatch.Capture],
        source: String
    ) -> Bool {
        switch predicate {
            case .eq(let capture, let value):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return text == value

            case .notEq(let capture, let value):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return text != value

            case .eqCapture(let capture, let other):
                guard let text = captureText(capture, captures: captures, source: source),
                    let otherText = captureText(other, captures: captures, source: source)
                else {
                    return false
                }
                return text == otherText

            case .notEqCapture(let capture, let other):
                guard let text = captureText(capture, captures: captures, source: source),
                    let otherText = captureText(other, captures: captures, source: source)
                else {
                    return false
                }
                return text != otherText

            case .match(let capture, let pattern):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return matchRegex(text: text, pattern: pattern)

            case .notMatch(let capture, let pattern):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return !matchRegex(text: text, pattern: pattern)

            case .anyOf(let capture, let values):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return values.contains(text)

            case .contains(let capture, let value):
                guard let text = captureText(capture, captures: captures, source: source) else {
                    return false
                }
                return text.contains(value)

            case .is(let capture, let property, let value):
                return hasProperty(property, value: value, capture: capture, captures: captures)

            case .isNot(let capture, let property, let value):
                return !hasProperty(property, value: value, capture: capture, captures: captures)

            case .directive:
                return true
        }
    }

    // MARK: - Private

    private static func captureText(
        _ captureName: String,
        captures: [QueryMatch.Capture],
        source: String
    ) -> String? {
        let name = captureName.hasPrefix("@") ? String(captureName.dropFirst()) : captureName
        guard let capture = captures.first(where: { $0.name == name }) else { return nil }
        return capture.node.text(from: source)
    }

    private static func matchRegex(text: String, pattern: String) -> Bool {
        guard let regex = regexCache.regex(for: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Whether the captured node has `property`, for `#is?` and `#is-not?`.
    ///
    /// A node has `named`, `error` and `extra` as its flags say; a property with a value is none of them. `local`
    /// asks whether the node is a local variable, which tree-sitter's highlighter learns from a locals query
    /// (`non_local_variable_patterns` in tree-sitter-highlight): with none, no node is one, so `#is-not? local`
    /// always holds and `#is? local` never does. This evaluator reads no locals query, as KittyCode ships none. Any
    /// other property, or a missing capture, is not had.
    private static func hasProperty(
        _ property: String,
        value: String?,
        capture captureName: String?,
        captures: [QueryMatch.Capture]
    ) -> Bool {
        guard value == nil, let captureName else { return false }
        let name = captureName.hasPrefix("@") ? String(captureName.dropFirst()) : captureName
        guard let capture = captures.first(where: { $0.name == name }) else { return false }

        switch property {
            case "named":
                return capture.node.isNamed
            case "error":
                return capture.node.isError
            case "extra":
                return capture.node.isExtra
            default:
                return false
        }
    }
}

// MARK: - Thread-safe regex cache

private final class RegexCache: Sendable {
    /// LRU upper bound — protects against a malformed query file that hands
    /// us a stream of unique patterns and would otherwise grow the cache
    /// without limit. 64 is comfortably above the predicate count any real
    /// language query ships with.
    private static let maxEntries = 64

    private struct CacheState {
        // `NSRegularExpression` is documented thread-safe, so the dictionary
        // value type is naturally Sendable — no `@unchecked` escape hatch
        // needed. The lock guards the dictionary mutation itself.
        var regexes: [String: NSRegularExpression] = [:]
        /// FIFO of pattern strings in insertion order; oldest is at index 0.
        var insertionOrder: [String] = []
    }

    private let storage = Mutex(CacheState())

    func regex(for pattern: String) -> NSRegularExpression? {
        storage.withLock { cache in
            if let existing = cache.regexes[pattern] { return existing }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            if cache.regexes.count >= Self.maxEntries, !cache.insertionOrder.isEmpty {
                let oldest = cache.insertionOrder.removeFirst()
                cache.regexes.removeValue(forKey: oldest)
            }
            cache.regexes[pattern] = regex
            cache.insertionOrder.append(pattern)
            return regex
        }
    }
}
