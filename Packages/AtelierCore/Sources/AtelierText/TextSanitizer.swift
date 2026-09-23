import Foundation

public enum TextSanitizer {
    public struct Result {
        public let text: String
        public let replacedCount: Int
    }

    /// Whether `scalar` is a C0 control (U+0000–U+001F), DEL (U+007F) or a C1 control (U+0080–U+009F): a code point
    /// a terminal can read as part of a command rather than as text.
    @inlinable
    public static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7F ... 0x9F).contains(scalar.value)
    }

    /// `input` without its controls other than tab and line feed, and without zero-width characters; each removed
    /// scalar counts in `replacedCount`.
    /// - Complexity: O(n) in the scalars of `input`.
    public static func sanitize(_ input: String) -> Result {
        var replaced = 0
        var result = ""

        for scalar in input.unicodeScalars {
            let value = scalar.value

            if isControl(scalar), value != 0x0A, value != 0x09 {
                result.append("")
                replaced += 1
            } else if [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060].contains(value) {
                result.append("")
                replaced += 1
            } else if value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
                result.append("")
                replaced += 1
            } else {
                result.append(Character(scalar))
            }
        }

        return Result(text: result, replacedCount: replaced)
    }
}
