import Foundation
import KittyParser

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
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return text == value

        case .notEq(let capture, let value):
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return text != value

        case .match(let capture, let pattern):
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return matchRegex(text: text, pattern: pattern)

        case .notMatch(let capture, let pattern):
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return !matchRegex(text: text, pattern: pattern)

        case .anyOf(let capture, let values):
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return values.contains(text)

        case .contains(let capture, let value):
            guard let text = captureText(capture, captures: captures, source: source) else { return false }
            return text.contains(value)

        case .is(let capture, let property):
            return checkProperty(capture, property: property, expected: true, captures: captures)

        case .isNot(let capture, let property):
            return checkProperty(capture, property: property, expected: false, captures: captures)
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

#if canImport(os)
import os
#endif

private final class RegexCache: Sendable {
    #if canImport(os)
    private let storage = OSAllocatedUnfairLock(initialState: [String: NSRegularExpression]())
    #else
    private let _lock = NSLock()
    private let _storage = NSMutableDictionary()
    #endif

    func regex(for pattern: String) -> NSRegularExpression? {
        #if canImport(os)
        return storage.withLock { cache in
            if let existing = cache[pattern] { return existing }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            cache[pattern] = regex
            return regex
        }
        #else
        _lock.lock()
        defer { _lock.unlock() }
        if let existing = _storage[pattern] as? NSRegularExpression { return existing }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        _storage[pattern] = regex
        return regex
        #endif
    }
}
