import AtelierParser
import Foundation

/// One test of a tree-sitter `test/corpus` file: an input and the tree tree-sitter parses it into, read the way
/// `tree-sitter test` reads the file.
struct UpstreamCorpusCase {
    var file: String
    var name: String
    var input: String
    /// The expected tree with comments, whitespace and field labels normalised away; nil when it does not parse.
    var expected: CorpusTreeNode?
    /// Whether the case is marked `:skip` or `:cst`, or is for another grammar's `:language`.
    var isSkipped: Bool
    /// Whether tree-sitter recovers from an error in the input: the case is marked `:error`, or its tree holds an
    /// `ERROR`, `MISSING` or `UNEXPECTED` node. That recovery is tree-sitter's own, which this parser does not mimic.
    var expectsError: Bool

    /// The cases of a corpus file, `contents`, named `file`, for the grammar `language`.
    ///
    /// A header is a line of three or more `=`, the test's name and markers on the lines after it, and another such
    /// line; the suffix after the first header's `=` must end every header and divider of the file. The input runs
    /// from the header to the longest line of three or more `-` before the next header, less one line break, and the
    /// expected tree follows that line.
    static func cases(in contents: String, file: String, language: String) -> [UpstreamCorpusCase] {
        let lines = CorpusLine.split(contents)
        let headers = CorpusHeader.headers(in: lines)
        guard let suffix = headers.first?.suffix else { return [] }
        let utf8 = Array(contents.utf8)
        var cases: [UpstreamCorpusCase] = []
        for (offset, header) in headers.enumerated() {
            let bodyEnd = offset + 1 < headers.count ? headers[offset + 1].start : utf8.count
            // The longest divider, the last of equally long ones, as `tree-sitter test` picks it.
            var divider: CorpusLine?
            for line in lines where line.start >= header.end && line.end <= bodyEnd && line.delimiter("-") == suffix {
                if let current = divider, current.end - current.start > line.end - line.start { continue }
                divider = line
            }
            guard let divider else { continue }
            var inputBytes = utf8[header.end ..< divider.start]
            if inputBytes.last == UInt8(ascii: "\n") { inputBytes = inputBytes.dropLast() }
            if inputBytes.last == UInt8(ascii: "\r") { inputBytes = inputBytes.dropLast() }
            let expected = CorpusTreeNode.parse(
                expectedOutput: String(decoding: utf8[divider.end ..< bodyEnd], as: UTF8.self))
            let markers = Set(header.markers.map { String($0.prefix { $0 != "(" }) })
            let languages = header.markers.compactMap { marker -> String? in
                guard marker.hasPrefix(":language(") else { return nil }
                return String(marker.dropFirst(":language(".count).prefix { $0 != ")" })
            }
            cases.append(
                UpstreamCorpusCase(
                    file: file, name: header.name, input: String(decoding: inputBytes, as: UTF8.self),
                    expected: expected,
                    isSkipped: markers.contains(":skip") || markers.contains(":cst")
                        || !(languages.isEmpty || languages.contains(language)),
                    expectsError: markers.contains(":error") || (expected?.containsRecovery ?? false)))
        }
        return cases
    }
}

/// A test header: its name, its markers such as `:skip`, the suffix of its `=` lines, and the bytes it spans.
private struct CorpusHeader {
    var name: String
    var markers: [String]
    var suffix: Substring
    var start: Int
    var end: Int

    /// The headers of a file whose suffix is the first header's.
    static func headers(in lines: [CorpusLine]) -> [CorpusHeader] {
        var headers: [CorpusHeader] = []
        var index = 0
        while index < lines.count {
            guard let opening = lines[index].delimiter("="), headers.first.map({ $0.suffix == opening }) ?? true
            else {
                index += 1
                continue
            }
            var closing = index + 1
            while closing < lines.count, !lines[closing].text.isEmpty, lines[closing].delimiter("=") == nil {
                closing += 1
            }
            guard closing > index + 1, closing < lines.count, lines[closing].delimiter("=") == opening else {
                index += 1
                continue
            }
            let body = lines[(index + 1) ..< closing].map { $0.text.trimmingCharacters(in: .whitespaces) }
            let markerStart = body.firstIndex { $0.hasPrefix(":") } ?? body.count
            headers.append(
                CorpusHeader(
                    name: body[..<markerStart].joined(separator: "\n"), markers: Array(body[markerStart...]),
                    suffix: opening, start: lines[index].start, end: lines[closing].end))
            index = closing + 1
        }
        return headers
    }
}

/// A line of a corpus file and the bytes it spans, its line break included.
private struct CorpusLine {
    var text: Substring
    var start: Int
    var end: Int

    static func split(_ contents: String) -> [CorpusLine] {
        var lines: [CorpusLine] = []
        let byteCount = contents.utf8.count
        var offset = 0
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.utf8.count
            let end = min(offset + length + 1, byteCount)
            lines.append(CorpusLine(text: line.hasSuffix("\r") ? line.dropLast() : line, start: offset, end: end))
            offset += length + 1
        }
        return lines
    }

    /// What follows a run of three or more `character` that starts the line, "" when nothing does; nil when the line
    /// is no such delimiter.
    func delimiter(_ character: Character) -> Substring? {
        let run = text.prefix { $0 == character }
        guard run.count >= 3 else { return nil }
        return text.dropFirst(run.count)
    }
}

/// A node of a tree as `tree-sitter test` compares it without fields: named nodes only. Extras are left out of both
/// trees: this parser keeps them beside the root rather than where they occur.
struct CorpusTreeNode: Equatable {
    var type: String
    var children: [CorpusTreeNode]
    /// Where the node lies in the input; nil for a node of an expected tree.
    var byteRange: Range<Int>?

    static func == (lhs: CorpusTreeNode, rhs: CorpusTreeNode) -> Bool {
        lhs.type == rhs.type && lhs.children == rhs.children
    }

    /// Whether the tree holds a node only tree-sitter's error recovery makes.
    var containsRecovery: Bool {
        ["ERROR", "MISSING", "UNEXPECTED"].contains(type) || children.contains { $0.containsRecovery }
    }

    /// The tree without the nodes whose types are in `types`, and without their descendants.
    func removing(_ types: Set<String>) -> CorpusTreeNode {
        CorpusTreeNode(
            type: type, children: children.filter { !types.contains($0.type) }.map { $0.removing(types) },
            byteRange: byteRange)
    }

    /// The tree in a corpus file's S-expression form, cut after about `limit` characters.
    func sexp(limit: Int = 240) -> String {
        var text = "(" + type
        for child in children {
            guard text.count <= limit else { break }
            text += " " + child.sexp(limit: limit)
        }
        text += ")"
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// The tree of a corpus test's expected output, nil for an empty or unbalanced one. Comment lines (`;`), field
    /// labels (`name:`), and the tokens of `MISSING` and `UNEXPECTED` nodes are left out.
    static func parse(expectedOutput output: String) -> CorpusTreeNode? {
        let text = output.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(";") }
            .joined(separator: "\n")
        var stack: [CorpusTreeNode] = []
        var root: CorpusTreeNode?
        var expectsType = false
        for token in tokens(of: text) {
            if token == "(" {
                expectsType = true
            } else if token == ")" {
                guard let node = stack.popLast() else { return nil }
                if stack.isEmpty {
                    root = root ?? node
                } else {
                    stack[stack.count - 1].children.append(node)
                }
            } else if expectsType {
                stack.append(CorpusTreeNode(type: token, children: []))
                expectsType = false
            }
        }
        return stack.isEmpty ? root : nil
    }

    /// The parentheses and words of an S-expression; a quoted string, `"…"` or `'…'`, is one word.
    private static func tokens(of text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false
        for character in text {
            if let open = quote {
                current.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "(" || character == ")" {
                if !current.isEmpty { tokens.append(current) }
                current = ""
                tokens.append(String(character))
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else {
                if current.isEmpty, character == "\"" || character == "'" { quote = character }
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// The visible nodes of a parse, as tree-sitter prints them: an error node as `ERROR`, a named node whose type is
    /// not hidden, and in place of any other node its visible descendants. Extras are left out.
    static func visibleNodes(of node: SyntaxNode, hidden: Set<String>) -> [CorpusTreeNode] {
        guard !node.isExtra else { return [] }
        let children = node.children.flatMap { visibleNodes(of: $0, hidden: hidden) }
        if node.isError {
            return [CorpusTreeNode(type: "ERROR", children: children, byteRange: node.byteRange)]
        }
        guard node.isNamed, !node.type.hasPrefix("_"), !hidden.contains(node.type) else { return children }
        return [CorpusTreeNode(type: node.type, children: children, byteRange: node.byteRange)]
    }
}

/// Where a parse first departs from the expected tree, walking both in order.
struct CorpusDivergence {
    /// The types from the root down to the parent of the diverging nodes.
    var path: [String]
    /// The expected node, nil where the parse has a node too many.
    var expected: CorpusTreeNode?
    /// The parse's node, nil where it lacks one.
    var actual: CorpusTreeNode?

    /// The first divergence of `actual` from `expected`, nil when the trees are equal.
    static func first(expected: CorpusTreeNode, actual: CorpusTreeNode) -> CorpusDivergence? {
        guard expected.type == actual.type else {
            return CorpusDivergence(path: [], expected: expected, actual: actual)
        }
        for index in 0 ..< max(expected.children.count, actual.children.count) {
            let expectedChild = expected.children.indices.contains(index) ? expected.children[index] : nil
            let actualChild = actual.children.indices.contains(index) ? actual.children[index] : nil
            guard let expectedChild, let actualChild else {
                return CorpusDivergence(path: [expected.type], expected: expectedChild, actual: actualChild)
            }
            if var divergence = first(expected: expectedChild, actual: actualChild) {
                divergence.path.insert(expected.type, at: 0)
                return divergence
            }
        }
        return nil
    }
}
