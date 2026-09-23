import Foundation
package import SwiftUI

/// Renders hover markdown into an `AttributedString`: fenced code blocks verbatim in a monospaced font, the rest
/// through the markdown parser, as plain text where the parser fails.
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

/// Splits `markdown` on ` ``` ` fences into alternating prose and code, starting with prose; an unterminated
/// fence runs to the end as code.
private nonisolated func fenceSections(of markdown: String) -> [FenceSection] {
    let pieces = markdown.components(separatedBy: "```")
    guard pieces.count > 1 else { return [.prose(markdown)] }
    var sections: [FenceSection] = []
    for (index, piece) in pieces.enumerated() {
        if index.isMultiple(of: 2) {
            sections.append(.prose(piece))
        } else {
            var code = stripLanguageTag(piece)
            // The trailing newline belongs to the closing fence's line, not to the code.
            if code.hasSuffix("\n") { code.removeLast() }
            sections.append(.code(code))
        }
    }
    return sections
}

/// Drops a fence's opening line when it is a language tag or empty; a first line containing whitespace is code
/// and stays.
private nonisolated func stripLanguageTag(_ fenceBody: String) -> String {
    guard let newlineIndex = fenceBody.firstIndex(of: "\n") else { return fenceBody }
    let firstLine = fenceBody[fenceBody.startIndex ..< newlineIndex]
    guard !firstLine.contains(where: \.isWhitespace) else { return fenceBody }
    return String(fenceBody[fenceBody.index(after: newlineIndex)...])
}
