import Foundation

/// Parses the hover markdown sourcekit-lsp and the doc-comment index produce into plain-text pieces: a leading
/// fenced declaration, a summary paragraph and discussion, a `- Parameters:` list or `- Parameter name:` items, and a
/// `- Returns:` item, each callout matched whatever its case. Blocks
/// separated by a `---` line are overload candidates; the first is the primary document.
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
        // A `/** */` comment in a file with CRLF line endings keeps them; every rule below splits on "\n".
        let blocks = splitBlocks(markdown.replacingOccurrences(of: "\r\n", with: "\n"))
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

    /// Splits on the `---` lines that separate overload candidates, dropping the "## Multiple results" heading and
    /// empty blocks. A separator stands outside every fence and opens onto the next candidate's fenced declaration, so
    /// a thematic break in the prose, or a `---` line inside a code block, stays in its block.
    private static func splitBlocks(_ markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [[String]] = [[]]
        var fence = FenceTracker()
        for (index, line) in lines.enumerated() {
            let wasInFence = fence.isOpen
            fence.consume(line)
            if !wasInFence, line.trimmingCharacters(in: .whitespaces) == "---", leadingSpaces(line) < 4,
                nextNonBlankLine(in: lines, after: index).map(FenceTracker.opensFence) == true
            {
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

    private static func nextNonBlankLine(in lines: [String], after index: Int) -> String? {
        lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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
        let (summary, discussion) = splitAbstract(proseLines)
        var block = ParsedBlock()
        block.declaration = declaration
        block.summary = summary
        block.discussion = discussion
        block.parameters = parameters
        block.returns = returns
        return block
    }

    /// The prose's opening paragraph, its abstract, and the rest verbatim, every line's indentation kept so indented
    /// code blocks stay code. No abstract when the prose opens with anything but a paragraph, such as a code block, a
    /// heading or a list.
    private static func splitAbstract(_ lines: [String]) -> (summary: String?, discussion: String?) {
        var body = ArraySlice(lines)
        while let first = body.first, isBlank(first) { body = body.dropFirst() }
        while let last = body.last, isBlank(last) { body = body.dropLast() }
        guard let first = body.first else { return (nil, nil) }
        guard !opensOtherBlock(first) else { return (nil, discussion(from: body)) }
        var end = body.startIndex + 1
        while end < body.endIndex, !isBlank(body[end]), !interruptsParagraph(body[end]) { end += 1 }
        // A paragraph underlined by `===` or `---` is a heading; the loop stops at a `---` line and runs over `===`.
        let underlineRange = (body.startIndex + 1) ..< min(end + 1, body.endIndex)
        if body[underlineRange].contains(where: isSetextUnderline) {
            return (nil, discussion(from: body))
        }
        let summary = body[body.startIndex ..< end].joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        return (summary, discussion(from: body[end...]))
    }

    private static func discussion(from lines: ArraySlice<String>) -> String? {
        var lines = lines
        while let first = lines.first, isBlank(first) { lines = lines.dropFirst() }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether `line` starts a block other than a paragraph: an indented or fenced code block, a heading, a quote, a
    /// list item or a thematic break.
    private static func opensOtherBlock(_ line: String) -> Bool {
        guard leadingSpaces(line) < 4 else { return true }
        if interruptsParagraph(line) { return true }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        let afterDigits = trimmed.dropFirst(digits.count)
        return !digits.isEmpty && (afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") "))
    }

    /// Whether `line` ends the paragraph above it and starts another block: a fence, a heading, a quote, a bullet
    /// item or a thematic break. An indented line continues the paragraph instead.
    private static func interruptsParagraph(_ line: String) -> Bool {
        guard leadingSpaces(line) < 4 else { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if FenceTracker.opensFence(line) || atxHeadingLevel(line) != nil || trimmed.hasPrefix(">") { return true }
        if ["- ", "* ", "+ "].contains(where: { trimmed.hasPrefix($0) }) { return true }
        return isThematicBreak(trimmed)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { !$0.isWhitespace }
        guard marks.count >= 3, let mark = marks.first, "-*_".contains(mark) else { return false }
        return marks.allSatisfy { $0 == mark }
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard leadingSpaces(line) < 4, let mark = trimmed.first, mark == "=" || mark == "-" else { return false }
        return trimmed.allSatisfy { $0 == mark }
    }

    /// The count of spaces opening `line`, a tab counting as four.
    private static func leadingSpaces(_ line: String) -> Int {
        var count = 0
        for character in line {
            switch character {
                case " ": count += 1
                case "\t": count += 4
                default: return count
            }
        }
        return count
    }

    /// The block's leading fenced declaration and everything after its closing fence; a nil declaration when the
    /// block does not open with a fence.
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

    /// Drops declaration lines that start with an underscored, compiler-internal attribute such as `@_specialize`,
    /// as Xcode's Quick Help does.
    private static func stripUnderscoredAttributeLines(_ declaration: String) -> String {
        let lines = declaration.components(separatedBy: "\n")
        let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("@_") }
        return kept.joined(separator: "\n")
    }

    /// Pulls a `- Parameters:` list, `- Parameter name:` items and a `- Returns:` item out of `lines`, in whatever
    /// order and position they appear, the parameters in the order they come; everything else is prose, in its
    /// original order, less any heading the fields leave with nothing under it.
    private static func extractLists(_ lines: [String]) -> (prose: [String], parameters: [Field], returns: String?) {
        // A nil line stands where a field was drawn out.
        var prose: [String?] = []
        var parameters: [Field] = []
        var returns: String?
        var fence = FenceTracker()
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            let wasInFence = fence.isOpen
            fence.consume(lines[index])
            // A code block's lines are prose, whatever they say.
            if wasInFence || fence.isOpen || leadingSpaces(lines[index]) >= 4 {
                prose.append(lines[index])
                index += 1
                continue
            }
            if callout("Parameters:", opening: trimmed)?.isEmpty == true {
                prose.append(nil)
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
            if let (name, text) = singularParameter(trimmed) {
                prose.append(nil)
                var fieldText = text
                index += 1
                while index < lines.count, isContinuation(lines[index]) {
                    fieldText += " " + lines[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                }
                parameters.append(Field(name: name, text: fieldText))
                continue
            }
            if let rest = callout("Returns:", opening: trimmed) {
                prose.append(nil)
                var text = rest.trimmingCharacters(in: .whitespaces)
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
        return (droppingHeadingsEmptiedByFields(prose), parameters, returns)
    }

    /// The name and text of a `- Parameter name: text` item, the form that documents one parameter on its own; nil
    /// for any other line, and for an item whose name is empty or holds a space.
    private static func singularParameter(_ trimmed: String) -> (name: String, text: String)? {
        guard let rest = callout("Parameter ", opening: trimmed), let colon = rest.firstIndex(of: ":") else {
            return nil
        }
        let name = rest[rest.startIndex ..< colon]
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return nil }
        let text = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (String(name), text)
    }

    /// What follows `- ` and `keyword` at the start of `trimmed`, the keyword matched whatever its case, as Swift's
    /// markup reads its callouts; nil when the line opens with anything else.
    private static func callout(_ keyword: String, opening trimmed: String) -> Substring? {
        guard trimmed.hasPrefix("- ") else { return nil }
        let afterBullet = trimmed.dropFirst(2)
        guard afterBullet.count >= keyword.count,
            afterBullet.prefix(keyword.count).caseInsensitiveCompare(keyword) == .orderedSame
        else { return nil }
        return afterBullet.dropFirst(keyword.count)
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

// MARK: - Headings
// Kept outside the enum body so it stays under `type_body_length`.
extension HoverMarkdownStructurer {
    /// `lines` without their nil lines, the fields drawn out, and without any heading whose section held nothing but
    /// fields: the fields show in sections of their own, and the heading would stand over nothing. A section runs to
    /// the next heading of its level or above, so a heading left empty by the removal of its subsections goes too.
    fileprivate static func droppingHeadingsEmptiedByFields(_ lines: [String?]) -> [String] {
        var lines = lines
        var headings: [(index: Int, span: Int, level: Int)] = []
        var fence = FenceTracker()
        var index = 0
        while index < lines.count {
            guard let line = lines[index] else {
                index += 1
                continue
            }
            let wasInFence = fence.isOpen
            fence.consume(line)
            if !wasInFence, !fence.isOpen {
                if let level = atxHeadingLevel(line) {
                    headings.append((index, 1, level))
                } else if index + 1 < lines.count, let underline = lines[index + 1], isSetextUnderline(underline),
                    !isBlank(line), !opensOtherBlock(line), index == 0 || lines[index - 1].map(isBlank) ?? true
                {
                    headings.append((index, 2, underline.contains("=") ? 1 : 2))
                    index += 2
                    continue
                }
            }
            index += 1
        }
        for (position, heading) in headings.enumerated().reversed() {
            let bodyStart = heading.index + heading.span
            let bodyEnd =
                headings[(position + 1)...].first { $0.level <= heading.level && lines[$0.index] != nil }?.index
                ?? lines.count
            let body = lines[bodyStart ..< bodyEnd]
            guard body.contains(where: { $0 == nil }), body.allSatisfy({ $0.map(isBlank) ?? true }) else { continue }
            for line in heading.index ..< bodyStart { lines[line] = nil }
        }
        return lines.compactMap(\.self)
    }

    /// The level of the ATX heading `line` opens, `#` to `######`; nil when it is no such heading.
    fileprivate static func atxHeadingLevel(_ line: String) -> Int? {
        guard leadingSpaces(line) < 4 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }.count
        let afterHashes = trimmed.dropFirst(hashes)
        guard (1 ... 6).contains(hashes), afterHashes.isEmpty || afterHashes.first == " " else { return nil }
        return hashes
    }
}

/// Follows fenced code blocks line by line: a fence of three or more backticks or tildes, indented less than four
/// spaces, opens a block that a fence of the same character, at least as long and with nothing after it, closes.
private struct FenceTracker {
    private var open: (mark: Character, length: Int)?

    var isOpen: Bool { open != nil }

    static func opensFence(_ line: String) -> Bool { fence(in: line) != nil }

    mutating func consume(_ line: String) {
        guard let fence = Self.fence(in: line) else { return }
        guard let current = open else {
            open = fence
            return
        }
        let rest = line.trimmingCharacters(in: .whitespaces).drop { $0 == current.mark }
        if fence.mark == current.mark, fence.length >= current.length, rest.isEmpty { open = nil }
    }

    private static func fence(in line: String) -> (mark: Character, length: Int)? {
        let indent = line.prefix { $0 == " " }.count
        guard indent < 4 else { return nil }
        let trimmed = line.dropFirst(indent)
        guard let mark = trimmed.first, mark == "`" || mark == "~" else { return nil }
        let length = trimmed.prefix { $0 == mark }.count
        return length >= 3 ? (mark, length) : nil
    }
}
