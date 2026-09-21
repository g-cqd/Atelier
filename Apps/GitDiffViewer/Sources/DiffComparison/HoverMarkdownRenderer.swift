import Foundation
package import SwiftUI

/// Renders hover documentation markdown into an `AttributedString` for the hover popover: fenced code blocks
/// (a signature, typically) are shown monospaced and verbatim, with no markdown interpretation inside them, so a
/// `*`, `_` or back-tick in code is never mistaken for emphasis or a nested code span; everything else goes
/// through `AttributedString`'s own markdown parser, falling back to plain text for a section that parser
/// rejects rather than showing nothing.
package nonisolated func renderHoverMarkdown(_ markdown: String) -> AttributedString {
    var result = AttributedString()
    for section in fenceSections(of: markdown) {
        switch section {
            case .code(let text):
                guard !text.isEmpty else { continue }
                var code = AttributedString(text)
                code.font = .system(.body, design: .monospaced)
                if !result.characters.isEmpty { result += AttributedString("\n") }
                result += code
            case .prose(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if !result.characters.isEmpty { result += AttributedString("\n") }
                result += parseProse(text)
        }
    }
    return result
}

private nonisolated func parseProse(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: text, options: options) else {
        return AttributedString(text)
    }
    return parsed
}

/// One piece of markdown: either inside a fenced code block or outside every fence.
private enum FenceSection {
    case code(String)
    case prose(String)
}

/// Splits `markdown` on ` ``` ` fences, alternating prose and code starting with prose. An unterminated fence
/// (an odd number of markers) treats everything from the last opening marker to the end as code, the same way a
/// markdown renderer typically shows a document that forgot to close its fence.
private nonisolated func fenceSections(of markdown: String) -> [FenceSection] {
    let pieces = markdown.components(separatedBy: "```")
    guard pieces.count > 1 else { return [.prose(markdown)] }
    var sections: [FenceSection] = []
    for (index, piece) in pieces.enumerated() {
        if index.isMultiple(of: 2) {
            sections.append(.prose(piece))
        } else {
            var code = stripLanguageTag(piece)
            // The closing fence sits on its own line, so the code capture between the markers carries one
            // trailing newline that belongs to that line, not to the code itself.
            if code.hasSuffix("\n") { code.removeLast() }
            sections.append(.code(code))
        }
    }
    return sections
}

/// A fence's own opening line is a language tag (` ```swift `) or empty (` ``` ` alone); either way the code
/// itself starts on the next line. A first line containing whitespace is not a tag at all -- an unlabeled fence
/// whose code happens to start immediately after the marker on the same line as more than one word -- so it is
/// left alone rather than dropped.
private nonisolated func stripLanguageTag(_ fenceBody: String) -> String {
    guard let newlineIndex = fenceBody.firstIndex(of: "\n") else { return fenceBody }
    let firstLine = fenceBody[fenceBody.startIndex ..< newlineIndex]
    guard !firstLine.contains(where: \.isWhitespace) else { return fenceBody }
    return String(fenceBody[fenceBody.index(after: newlineIndex)...])
}
