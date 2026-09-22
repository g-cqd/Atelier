import Foundation

/// Parses the markdown shapes sourcekit-lsp and the doc-comment index actually produce into plain-text pieces
/// (``HoverDocument`` colors and styles them afterward, given the palette the resolver was hovering over):
///
/// - A leading fenced declaration, then an abstract paragraph and further discussion prose.
/// - A `- Parameters:` list, its items one per parameter (`- name: description`), and a `- Returns:` item.
/// - Multiple candidates (sourcekit-lsp's "## Multiple results" overload list, and the doc-comment index's own
///   multi-entry answer) joined by a line that is exactly `---`; only the first is the primary document, the rest
///   become ``HoverMarkdownStructurer/Document/extraCandidates``.
package enum HoverMarkdownStructurer {
    package struct Field: Sendable, Equatable {
        package let name: String
        package let text: String

        package init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    package struct Candidate: Sendable, Equatable {
        package let declaration: String?
        package let summary: String?

        package init(declaration: String?, summary: String?) {
            self.declaration = declaration
            self.summary = summary
        }
    }

    package struct Document: Sendable, Equatable {
        package var declaration: String?
        package var summary: String?
        package var discussion: String?
        package var parameters: [Field] = []
        package var returns: String?
        package var extraCandidates: [Candidate] = []

        package init() {}
    }

    package static func structure(_ markdown: String) -> Document {
        let blocks = splitBlocks(markdown)
        guard let firstBlock = blocks.first else { return Document() }
        let primary = parseBlock(firstBlock)
        var document = Document()
        document.declaration = primary.declaration
        document.summary = primary.summary
        document.discussion = primary.discussion
        document.parameters = primary.parameters
        document.returns = primary.returns
        document.extraCandidates = blocks.dropFirst().prefix(2)
            .map { block in
                let parsed = parseBlock(block)
                return Candidate(declaration: parsed.declaration, summary: parsed.summary)
            }
        return document
    }

    // MARK: Block splitting

    /// Splits on a line that is exactly `---`, and drops a leading "## Multiple results" heading, which carries
    /// no content of its own; empty blocks (a stray leading/trailing separator) are dropped.
    private static func splitBlocks(_ markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [[String]] = [[]]
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                blocks.append([])
            } else {
                blocks[blocks.count - 1].append(line)
            }
        }
        return
            blocks
            .map { lines -> String in
                var text = lines.joined(separator: "\n")
                if let headingRange = text.range(of: "## Multiple results") {
                    text.removeSubrange(headingRange)
                }
                return text
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Block parsing

    private struct ParsedBlock {
        var declaration: String?
        var summary: String?
        var discussion: String?
        var parameters: [Field] = []
        var returns: String?
    }

    private static func parseBlock(_ text: String) -> ParsedBlock {
        let (declaration, rest) = extractLeadingDeclaration(text)
        let lines = rest.components(separatedBy: "\n")
        let (proseLines, parameters, returns) = extractLists(lines)
        let proseText = proseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs =
            proseText.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var block = ParsedBlock()
        block.declaration = declaration
        block.summary = paragraphs.first
        block.discussion = paragraphs.count > 1 ? paragraphs.dropFirst().joined(separator: "\n\n") : nil
        block.parameters = parameters
        block.returns = returns
        return block
    }

    /// The block's own leading fenced code (a declaration, `sourcekit-lsp` and the doc-comment index both put one
    /// first), and everything after its closing fence. `nil` when the block does not open with a fence.
    private static func extractLeadingDeclaration(_ text: String) -> (declaration: String?, rest: String) {
        let leading = text.drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" })
        guard leading.hasPrefix("```") else { return (nil, text) }
        let afterOpen = leading.index(leading.startIndex, offsetBy: 3)
        guard let closeRange = leading.range(of: "```", range: afterOpen ..< leading.endIndex) else {
            return (nil, text)
        }
        var body = String(leading[afterOpen ..< closeRange.lowerBound])
        // The fence's own opening line is a language tag or empty; the code itself starts on the next line.
        if let newlineIndex = body.firstIndex(of: "\n") {
            let firstLine = body[body.startIndex ..< newlineIndex]
            if !firstLine.contains(where: \.isWhitespace) {
                body = String(body[body.index(after: newlineIndex)...])
            }
        }
        if body.hasSuffix("\n") { body.removeLast() }
        let rest = String(leading[closeRange.upperBound...])
        return (stripUnderscoredAttributeLines(body), rest)
    }

    /// Drops any declaration line that is nothing but an underscored (`@_`-prefixed) attribute -- compiler-internal
    /// annotations such as `@_originallyDefinedIn(module: "...", ...)` or `@_specialize(...)` that sourcekit-lsp's
    /// declaration answers sometimes carry for a system symbol, and that Xcode's own Quick Help hides. A public
    /// attribute (`@MainActor`, `@frozen`, `@propertyWrapper`, `@preconcurrency`, ...) never starts with the `_`
    /// sigil, so this only ever removes the underscored ones.
    private static func stripUnderscoredAttributeLines(_ declaration: String) -> String {
        let lines = declaration.components(separatedBy: "\n")
        let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("@_") }
        return kept.joined(separator: "\n")
    }

    /// Pulls a `- Parameters:` list and a `- Returns:` item out of `lines`, in whatever order and position they
    /// appear; everything else is prose, in its original order.
    private static func extractLists(_ lines: [String]) -> (prose: [String], parameters: [Field], returns: String?) {
        var prose: [String] = []
        var parameters: [Field] = []
        var returns: String?
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "- Parameters:" {
                index += 1
                while index < lines.count, isIndented(lines[index]) {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    guard item.hasPrefix("- "), let colonRange = item.range(of: ": ") else {
                        index += 1
                        continue
                    }
                    let name = String(item[item.index(item.startIndex, offsetBy: 2) ..< colonRange.lowerBound])
                    var fieldText = String(item[colonRange.upperBound...])
                    index += 1
                    while index < lines.count, isContinuation(lines[index]) {
                        fieldText += " " + lines[index].trimmingCharacters(in: .whitespaces)
                        index += 1
                    }
                    parameters.append(Field(name: name, text: fieldText))
                }
                continue
            }
            if trimmed.hasPrefix("- Returns:") {
                var text = String(trimmed.dropFirst("- Returns:".count)).trimmingCharacters(in: .whitespaces)
                index += 1
                while index < lines.count, isContinuation(lines[index]) {
                    text += " " + lines[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
                returns = text.isEmpty ? nil : text
                continue
            }
            prose.append(lines[index])
            index += 1
        }
        return (prose, parameters, returns)
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    /// A continuation of the previous list item: indented, but not itself the start of a new `- ` item.
    private static func isContinuation(_ line: String) -> Bool {
        guard isIndented(line) else { return false }
        return !line.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
    }
}
