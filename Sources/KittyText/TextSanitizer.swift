import Foundation

public enum TextSanitizer {
    public struct Result {
        public let text: String
        public let replacedCount: Int
    }

    public static func sanitize(_ input: String) -> Result {
        var replaced = 0
        var result = ""

        for scalar in input.unicodeScalars {
            let value = scalar.value

            if (value < 0x20 && value != 0x0A && value != 0x09) || value == 0x7F {
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
