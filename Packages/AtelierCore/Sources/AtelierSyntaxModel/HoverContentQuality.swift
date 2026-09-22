import Foundation

/// Judges the quality of a ``HoverContent``'s markdown, so a composite hover provider can tell a genuine
/// documentation answer apart from a bare declaration with nothing said about it.
///
/// sourcekit-lsp and the doc-comment index both shape their answers the same way: an optional leading fenced
/// code block (the declaration), then prose. A symbol with no `///` comment and no indexed documentation still
/// answers with just the fenced declaration -- syntactically valid markdown, but nothing a reader would call
/// "documentation". This type recognizes that shape without needing ``HoverMarkdownStructurer`` (which lives in
/// the app layer, above this package) to parse the whole document.
public enum HoverContentQuality {
    /// Whether `markdown` says anything beyond its fenced code block(s): true when there is non-whitespace text
    /// outside every ` ``` ` fence. A whitespace-only remainder, or a document that is nothing but one or more
    /// fenced blocks, counts as having no prose.
    public static func hasProse(_ markdown: String) -> Bool {
        !stripFencedCodeBlocks(markdown).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `markdown`'s first fenced code block, fences included, when it opens with one (after leading whitespace) --
    /// the shape sourcekit-lsp and the doc-comment index both use for a leading declaration. `nil` when `markdown`
    /// does not open with a fence, or the fence is never closed.
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
