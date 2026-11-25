import Foundation

/// Judges a ``HoverContent``'s markdown, so a composite hover provider can tell documentation apart from a bare
/// declaration. Both sourcekit-lsp and the doc-comment index answer with an optional leading fenced declaration,
/// then prose.
public enum HoverContentQuality {
    /// Whether `markdown` has any non-whitespace text outside its ` ``` ` fenced blocks.
    public static func hasProse(_ markdown: String) -> Bool {
        !stripFencedCodeBlocks(markdown).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `markdown`'s leading fenced code block, fences included, after any leading whitespace; `nil` when `markdown`
    /// does not open with a closed fence.
    public static func leadingFencedBlock(_ markdown: String) -> String? {
        let leading = markdown.drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" })
        guard leading.hasPrefix("```") else { return nil }
        let afterOpen = leading.index(leading.startIndex, offsetBy: 3)
        guard let closeRange = leading.range(of: "```", range: afterOpen ..< leading.endIndex) else { return nil }
        return String(leading[leading.startIndex ..< closeRange.upperBound])
    }

    /// Removes every ` ``` ... ``` ` fenced block from `markdown` (an unterminated trailing fence is dropped along
    /// with everything after its opener), leaving whatever text surrounds them, in order.
    private static func stripFencedCodeBlocks(_ markdown: String) -> String {
        var result = ""
        var remainder = Substring(markdown)
        while let openRange = remainder.range(of: "```") {
            result += remainder[remainder.startIndex ..< openRange.lowerBound]
            guard let closeRange = remainder.range(of: "```", range: openRange.upperBound ..< remainder.endIndex)
            else {
                remainder = Substring("")
                break
            }
            remainder = remainder[closeRange.upperBound...]
        }
        result += remainder
        return result
    }
}
