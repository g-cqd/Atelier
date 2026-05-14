import Foundation
import KittyParser
import KittySync

/// Evaluates query predicates against captured nodes.
public enum Predicates: Sendable {

    /// Thread-safe regex cache to avoid recompiling patterns.
    private static let regexCache = RegexCache()

    public static func evaluate(
        _ predicate: Predicate,
        captures: [(node: SyntaxNode, name: String)],
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

        case .is(let capture, let property):
            return checkProperty(capture, property: property, expected: true, captures: captures)

        case .isNot(let capture, let property):
            return checkProperty(capture, property: property, expected: false, captures: captures)

        case .directive:
            return true
        }
    }

    // MARK: - Private

    private static func captureText(
        _ captureName: String,
        captures: [(node: SyntaxNode, name: String)],
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

    private static func checkProperty(
        _ captureName: String,
        property: String,
        expected: Bool,
        captures: [(node: SyntaxNode, name: String)]
    ) -> Bool {
        let name = captureName.hasPrefix("@") ? String(captureName.dropFirst()) : captureName
        guard let capture = captures.first(where: { $0.name == name }) else { return !expected }

        switch property {
        case "named":
            return capture.node.isNamed == expected
        case "error":
            return capture.node.isError == expected
        case "extra":
            return capture.node.isExtra == expected
        default:
            return !expected
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

    private let storage = StateLock(initialState: CacheState())

    func regex(for pattern: String) -> NSRegularExpression? {
        return storage.withLock { cache in
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
