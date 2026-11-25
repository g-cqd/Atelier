import Foundation

/// An immutable ICU expression for bounded search; replacement templates are expanded from its matches in the line
/// that was searched.
public struct SearchRegex: Sendable {
    let expression: NSRegularExpression

    init(pattern: String, caseSensitive: Bool) throws {
        let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive
        expression = try NSRegularExpression(pattern: pattern, options: options)
    }
}
