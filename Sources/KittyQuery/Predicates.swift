import Foundation
import KittyParser

/// Evaluates query predicates against captured nodes.
public enum Predicates: Sendable {

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
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
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
