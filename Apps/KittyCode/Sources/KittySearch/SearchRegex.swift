import Foundation

/// Immutable ICU expressions for bounded search and whole-match capture replacement.
public struct SearchRegex: Sendable {
    let expression: NSRegularExpression
    let wholeExpression: NSRegularExpression

    init(pattern: String, caseSensitive: Bool) throws {
        let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive
        expression = try NSRegularExpression(pattern: pattern, options: options)
        wholeExpression = try NSRegularExpression(pattern: "\\A(?:\(pattern))\\z", options: options)
    }
}
