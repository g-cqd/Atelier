public import AtelierSyntaxModel
import Foundation

/// How a language writes its doc comments, and how one reads as markdown.
///
/// - ``jsDoc``: a `/** … */` block, its lines' leading `*` stripped. Its `@param`, `@returns` and `@throws` tags
///   become the `- Parameter`, `- Returns` and `- Throws` callouts Swift's documentation uses, so a hover lays them
///   out alike; `{@link Name}` becomes code.
/// - ``goDoc``: the `//` lines right above a declaration, or one `/* … */` block. An indented line is code, a `# `
///   line between blank lines a heading, `[Name]` a code reference; `//go:` and other directives are dropped.
public enum DocCommentConvention: Sendable, Equatable {
    case jsDoc
    case goDoc

    /// The convention `language` documents its declarations with; nil for a language the lexical tier does not read.
    public static func convention(for language: Language) -> DocCommentConvention? {
        switch language {
            case .typescript, .javascript: .jsDoc
            case .go: .goDoc
            default: nil
        }
    }

    /// Whether `comment`, one comment token's text, can be part of a doc comment under this convention: a JSDoc
    /// block for ``jsDoc``, and any comment for ``goDoc``, whose directive lines, such as `//go:noinline` between a
    /// doc comment and its function, the markdown drops.
    public func admits(_ comment: Substring) -> Bool {
        switch self {
            case .jsDoc:
                return comment.hasPrefix("/**") && !comment.hasPrefix("/**/")
            case .goDoc:
                return comment.hasPrefix("/*") || comment.hasPrefix("//")
        }
    }

    /// The doc comment `text` as markdown: one JSDoc block, or a Go comment's lines joined by line breaks. Nil when
    /// nothing is left once the markers and tags that show nothing are gone.
    public func markdown(fromComment text: Substring) -> String? {
        let markdown =
            switch self {
                case .jsDoc: Self.jsDocMarkdown(Self.jsDocLines(text))
                case .goDoc: Self.goDocMarkdown(Self.goDocLines(text))
            }
        let trimmed = markdown.trimmingBlankLines()
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - JSDoc

    /// The lines of a `/** … */` block without its delimiters, and each line without the indentation and the `*` that
    /// lead it, nor the one space after that `*`.
    private static func jsDocLines(_ text: Substring) -> [Substring] {
        var body = text
        if body.hasPrefix("/**") { body = body.dropFirst(3) }
        if body.hasSuffix("*/") { body = body.dropLast(2) }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var line = line.drop { $0 == " " || $0 == "\t" }
                if line.first == "*" {
                    line = line.dropFirst()
                    if line.first == " " { line = line.dropFirst() }
                }
                return Substring(line.trimmingTrailingWhitespace())
            }
    }

    /// One `@tag` of a JSDoc block and the text after it, its continuation lines joined by line breaks.
    private struct JSDocTag {
        let name: Substring
        var text: String
    }

    private static func jsDocMarkdown(_ lines: [Substring]) -> String {
        var description: [String] = []
        var tags: [JSDocTag] = []
        var inFence = false
        for line in lines {
            if line.hasPrefix("```") { inFence.toggle() }
            if !inFence, line.hasPrefix("@"), let name = line.dropFirst().split(separator: " ").first {
                let rest = line.dropFirst(1 + name.count).drop { $0 == " " }
                tags.append(JSDocTag(name: name, text: String(rest)))
            } else if tags.isEmpty {
                description.append(String(line))
            } else {
                tags[tags.count - 1].text += "\n" + line
            }
        }
        var sections: [String] = []
        var callouts: [String] = []
        var parameters: [(name: String, text: String)] = []
        for tag in tags {
            switch tag.name {
                case "param", "arg", "argument":
                    if let parameter = parameter(tag.text) { parameters.append(parameter) }
                case "returns", "return":
                    callouts.append("- Returns: " + inline(typePrefixed(tag.text)))
                case "throws", "throw", "exception":
                    callouts.append("- Throws: " + inline(typePrefixed(tag.text)))
                case "deprecated":
                    sections.insert("**Deprecated.** " + inline(tag.text), at: 0)
                case "example":
                    sections.append("```\n" + tag.text.trimmingBlankLines() + "\n```")
                case "see":
                    callouts.append("- SeeAlso: " + inline(tag.text))
                default:
                    // `@type`, `@template`, `@private` and the like say nothing a reader needs.
                    continue
            }
        }
        var parameterCallouts: [String] = []
        if parameters.count == 1, let parameter = parameters.first {
            parameterCallouts = ["- Parameter \(parameter.name): \(parameter.text)"]
        } else if !parameters.isEmpty {
            parameterCallouts = ["- Parameters:"] + parameters.map { "  - \($0.name): \($0.text)" }
        }
        let body = inline(description.joined(separator: "\n")).trimmingBlankLines()
        let calloutBlock = (parameterCallouts + callouts).joined(separator: "\n")
        return ([body] + sections + [calloutBlock]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A `@param` tag's name and text: `{Type} name - text`, `name text` or `[name=default] text`; the type, when
    /// given, leads the text in code.
    private static func parameter(_ text: String) -> (name: String, text: String)? {
        var rest = Substring(text)
        var type: Substring?
        if rest.first == "{", let close = rest.firstIndex(of: "}") {
            type = rest[rest.index(after: rest.startIndex) ..< close]
            rest = rest[rest.index(after: close)...].drop { $0 == " " }
        }
        guard var name = rest.split(separator: " ", maxSplits: 1).first else { return nil }
        rest = rest.dropFirst(name.count).drop { $0 == " " }
        if name.hasPrefix("["), name.hasSuffix("]") {
            name = name.dropFirst().dropLast()
            name = name.split(separator: "=", maxSplits: 1).first ?? name
        }
        if rest.hasPrefix("- ") { rest = rest.dropFirst(2) }
        let described = inline(String(rest)).replacingOccurrences(of: "\n", with: " ")
        let text = type.map { "(`\($0)`) " + described } ?? described
        return (String(name), text.trimmingCharacters(in: .whitespaces))
    }

    /// A tag's text with its leading `{Type}` shown as code.
    private static func typePrefixed(_ text: String) -> String {
        guard text.first == "{", let close = text.firstIndex(of: "}") else { return text }
        let type = text[text.index(after: text.startIndex) ..< close]
        let rest = text[text.index(after: close)...].drop { $0 == " " }
        return "(`\(type)`) " + rest
    }

    /// `text` with each inline `{@link Name}`, `{@link Name|label}`, `{@linkcode Name}` or `{@linkplain Name}` shown
    /// as its label, or its name in code.
    private static func inline(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{@link") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].firstIndex(of: "}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let body = rest[open.upperBound ..< close].drop { $0 != " " }.drop { $0 == " " }
            let parts = body.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                result += parts[1]
            } else if let target = parts.first?.split(separator: " ", maxSplits: 1) {
                let label = target.count == 2 ? String(target[1]) : nil
                result += label ?? "`\(target.first ?? "")`"
            }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    // MARK: - godoc

    /// The lines of a Go comment without their markers: `//` and the one space after it, or a `/* … */` block's
    /// delimiters. Directive lines are dropped.
    private static func goDocLines(_ text: Substring) -> [Substring] {
        if text.hasPrefix("/*") {
            var body = text.dropFirst(2)
            if body.hasSuffix("*/") { body = body.dropLast(2) }
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
                .map {
                    Substring($0.trimmingTrailingWhitespace())
                }
            // The block's own indentation, the least of its lines', is not the code indentation of godoc.
            let indentation =
                lines.filter { !$0.isEmpty }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
            return lines.map { $0.dropFirst(indentation) }
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { raw in
                let line = raw.drop { $0 == " " || $0 == "\t" }
                guard line.hasPrefix("//") else { return nil }
                let body = line.dropFirst(2)
                if isDirective(body) { return nil }
                return Substring((body.first == " " ? body.dropFirst() : body).trimmingTrailingWhitespace())
            }
    }

    private static func goDocMarkdown(_ lines: [Substring]) -> String {
        var output: [String] = []
        var inCode = false
        for (offset, line) in lines.enumerated() {
            let indented = line.first == " " || line.first == "\t"
            let content = line.drop { $0 == " " || $0 == "\t" }
            let isListItem = indented && Self.startsListItem(content)
            if indented, !isListItem, !content.isEmpty {
                if !inCode {
                    output.append("```")
                    inCode = true
                }
                output.append(String(line.dropFirst(line.first == "\t" ? 1 : min(countLeadingSpaces(line), 4))))
                continue
            }
            // A blank line inside code stays in it while more code follows.
            if inCode, content.isEmpty, lines[(offset + 1)...].first(where: { !$0.isEmpty }).map(Self.isCode) == true {
                output.append("")
                continue
            }
            if inCode {
                output.append("```")
                inCode = false
            }
            let blankAround =
                (offset == 0 || lines[offset - 1].isEmpty) && (offset + 1 == lines.count || lines[offset + 1].isEmpty)
            if line.hasPrefix("# "), blankAround {
                output.append("### " + line.dropFirst(2))
            } else if isListItem {
                output.append(goLinks(String(content)))
            } else {
                output.append(goLinks(String(line)))
            }
        }
        if inCode { output.append("```") }
        return output.joined(separator: "\n")
    }

    private static func isCode(_ line: Substring) -> Bool {
        (line.first == " " || line.first == "\t") && !startsListItem(line.drop { $0 == " " || $0 == "\t" })
    }

    private static func startsListItem(_ content: Substring) -> Bool {
        if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") || content.hasPrefix("• ") {
            return true
        }
        let digits = content.prefix { $0.isASCII && $0.isNumber }
        return !digits.isEmpty && content.dropFirst(digits.count).hasPrefix(". ")
    }

    private static func countLeadingSpaces(_ line: Substring) -> Int {
        line.prefix { $0 == " " }.count
    }

    /// `text` with each doc link, `[Name]` or `[pkg.Name]`, shown as code; a Markdown link, `[text](url)`, stays.
    private static func goLinks(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "[") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "]") else {
                rest = rest[open...]
                break
            }
            let target = rest[afterOpen ..< close]
            let afterClose = rest.index(after: close)
            let isName = target.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "*" }
            let next = rest[afterClose...].first
            let isDocLink = !target.isEmpty && isName && next != "(" && next != ":"
            result += isDocLink ? "`\(target)`" : String(rest[open ... close])
            rest = rest[afterClose...]
        }
        return result + rest
    }

    /// Whether a `//` comment's body, the text after `//`, is a directive such as `go:generate` or `nolint:all`: a
    /// lowercase word and a colon, with no space after the slashes.
    private static func isDirective(_ body: Substring) -> Bool {
        guard let colon = body.firstIndex(of: ":") else { return false }
        let word = body[..<colon]
        return !word.isEmpty && word.allSatisfy { ($0.isASCII && $0.isLowercase) || $0.isNumber }
            && body[body.index(after: colon)...].first.map { $0 != " " } ?? false
    }
}

extension StringProtocol {
    /// The text without the spaces and tabs that end it.
    fileprivate func trimmingTrailingWhitespace() -> SubSequence {
        var end = endIndex
        while end > startIndex {
            let previous = index(before: end)
            guard self[previous] == " " || self[previous] == "\t" || self[previous] == "\r" else { break }
            end = previous
        }
        return self[startIndex ..< end]
    }

    /// The text without its leading and trailing blank lines.
    fileprivate func trimmingBlankLines() -> String {
        var lines = split(separator: "\n", omittingEmptySubsequences: false)
        while let first = lines.first, first.allSatisfy({ $0 == " " || $0 == "\t" }) { lines.removeFirst() }
        while let last = lines.last, last.allSatisfy({ $0 == " " || $0 == "\t" }) { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
